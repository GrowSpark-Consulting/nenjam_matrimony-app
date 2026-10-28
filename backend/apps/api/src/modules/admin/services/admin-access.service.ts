import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import { isUsableStaff } from '../rbac/assert-admin-permission';
import { isPermissionKey, type PermissionKey } from '../rbac/permissions';

export interface StaffAccount {
  userId: string;
  email: string;
  adminAccountId: string;
  department: string;
  mfaEnrolledAt: Date | null;
  lastLoginAt: Date | null;
}

export interface StaffGrants {
  roles: Array<{ key: string; name: string }>;
  permissions: PermissionKey[];
}

/**
 * Reads who is staff and what their roles grant — always from the database,
 * per request: admin traffic is tiny, and a role removed or an account
 * switched off must take effect on the very next request, not after a cache
 * expires.
 */
@Injectable()
export class AdminAccessService {
  constructor(private readonly prisma: PrismaService) {}

  /** The active staff account for [userId], or null if they are not one. */
  async loadStaff(userId: string): Promise<StaffAccount | null> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        role: true,
        status: true,
        deletedAt: true,
        adminAccount: {
          select: {
            id: true,
            isActive: true,
            department: true,
            mfaEnrolledAt: true,
            lastLoginAt: true,
          },
        },
      },
    });
    if (!isUsableStaff(user)) return null;
    return {
      userId: user.id,
      email: user.email,
      adminAccountId: user.adminAccount.id,
      department: user.adminAccount.department,
      mfaEnrolledAt: user.adminAccount.mfaEnrolledAt,
      lastLoginAt: user.adminAccount.lastLoginAt,
    };
  }

  async grantsFor(adminAccountId: string): Promise<StaffGrants> {
    const assignments = await this.prisma.adminUserRole.findMany({
      where: { adminAccountId },
      select: {
        role: {
          select: {
            key: true,
            name: true,
            permissions: { select: { permission: { select: { key: true } } } },
          },
        },
      },
      orderBy: { role: { key: 'asc' } },
    });
    const permissions = new Set<PermissionKey>();
    for (const { role } of assignments) {
      for (const { permission } of role.permissions) {
        // A key in the database that this build doesn't know (added by a
        // newer migration, say) guards nothing here, so it is not reported.
        if (isPermissionKey(permission.key)) permissions.add(permission.key);
      }
    }
    return {
      roles: assignments.map(({ role }) => ({
        key: role.key,
        name: role.name,
      })),
      permissions: [...permissions].sort(),
    };
  }
}
