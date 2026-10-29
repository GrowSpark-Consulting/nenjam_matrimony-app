import { isStaffRole } from '@app/common';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { adminForbidden } from '../auth/admin-auth.policy';
import type { PermissionKey } from './permissions';

/** The fields that decide whether a user may act as staff at all. */
export interface StaffCandidate {
  role: string;
  status: string;
  deletedAt: Date | null;
  adminAccount: { isActive: boolean } | null;
}

/**
 * Whether [user] may act as an admin at all, before any permission: an
 * ACTIVE, undeleted staff user whose AdminAccount has been switched on by
 * provisioning.
 */
export function isUsableStaff(
  user: StaffCandidate | null | undefined,
): user is StaffCandidate & { adminAccount: { isActive: true } } {
  return (
    !!user &&
    isStaffRole(user.role) &&
    user.status === 'ACTIVE' &&
    user.deletedAt === null &&
    user.adminAccount?.isActive === true
  );
}

/**
 * Who may perform an administrative operation — checked INSIDE the service's
 * transaction, against the same rows the change is about to depend on, so no
 * controller (or script) can skip it by forgetting a guard, and a role removed
 * a moment ago is already refused.
 *
 * Grants come from roles: AdminAccount → AdminUserRole → Role →
 * RolePermission → Permission. The legacy `AdminAccount.permissions` JSON is
 * not read.
 */
export async function assertAdminPermission(
  db: Pick<Prisma.TransactionClient, 'user'>,
  actorId: string,
  permission: PermissionKey,
): Promise<void> {
  // The same body AdminGuard sends, so a client handles a refusal from a
  // service exactly like one from the guard.
  const denied = () =>
    adminForbidden(
      'ADMIN_PERMISSION_DENIED',
      `Not permitted: requires ${permission}.`,
      { missing: [permission] },
    );
  if (typeof actorId !== 'string' || actorId.length === 0) throw denied();

  const actor = await db.user.findUnique({
    where: { id: actorId },
    select: {
      role: true,
      status: true,
      deletedAt: true,
      adminAccount: {
        select: {
          isActive: true,
          roles: {
            where: {
              role: {
                permissions: { some: { permission: { key: permission } } },
              },
            },
            select: { roleId: true },
            take: 1,
          },
        },
      },
    },
  });
  if (!isUsableStaff(actor) || actor.adminAccount.roles.length === 0) {
    throw denied();
  }
}
