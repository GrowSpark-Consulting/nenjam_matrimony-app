import type { PrismaClient } from '@app/database';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { ADMIN_ENROLLMENT_CODE_TTL_MS } from '../auth/admin-auth.policy';
import { hashEnrollmentCode, newEnrollmentCode } from '../auth/secret-box';
import { revokeAllAdminSessions } from '../services/admin-session.service';

/**
 * Operator-side administration of staff accounts, run by
 * `pnpm admin:provision` (scripts/admin-provision.ts). There is no HTTP route
 * that can create an admin or grant a role yet: the first admins must come
 * from someone with database and Firebase credentials, and every action here
 * is audited with a reason and `actorId: null`.
 *
 * Rules:
 *  - An admin is a dedicated staff identity: a member account (one with a
 *    profile) is never promoted. Create a separate staff email instead.
 *  - The Firebase account must already exist (created by the operator in the
 *    Firebase console); this links the staff row to it and nothing else can.
 *  - A newly provisioned (or reset) admin gets a one-time enrolment code,
 *    valid 24 hours, to set up their authenticator. It is returned once and
 *    only its hash is stored — hand it over out of band.
 */
export class ProvisioningError extends Error {}

type Db = Pick<PrismaClient, '$transaction' | 'user' | 'role' | 'adminAccount'>;

export interface GrantAdminRoleInput {
  firebaseUid: string;
  email: string;
  roleKey: string;
  reason: string;
}

export interface GrantAdminRoleResult {
  userId: string;
  adminAccountId: string;
  createdUser: boolean;
  roleAdded: boolean;
  /** Set when the admin has no authenticator yet. Shown once. */
  enrollmentCode: string | null;
}

export async function grantAdminRole(
  db: Db,
  input: GrantAdminRoleInput,
  now: Date = new Date(),
): Promise<GrantAdminRoleResult> {
  assertReason(input.reason);
  const email = input.email.trim().toLowerCase();
  const role = await db.role.findUnique({ where: { key: input.roleKey } });
  if (!role) throw new ProvisioningError(`No role "${input.roleKey}".`);

  const byUid = await db.user.findUnique({
    where: { firebaseUid: input.firebaseUid },
    select: USER_CHECK,
  });
  const byEmail = await db.user.findUnique({
    where: { email },
    select: USER_CHECK,
  });
  if (byUid && byEmail && byUid.id !== byEmail.id) {
    throw new ProvisioningError(
      `The Firebase account and the email belong to two different users ` +
        `(${byUid.id}, ${byEmail.id}). Resolve that by hand first.`,
    );
  }
  const existing = byUid ?? byEmail;
  if (existing) assertPromotable(existing);

  return db.$transaction(async (tx) => {
    const user = existing
      ? await tx.user.update({
          where: { id: existing.id },
          data: {
            firebaseUid: input.firebaseUid,
            email,
            role: 'ADMIN',
            status: 'ACTIVE',
          },
          select: { id: true },
        })
      : await tx.user.create({
          data: {
            firebaseUid: input.firebaseUid,
            email,
            role: 'ADMIN',
            status: 'ACTIVE',
          },
          select: { id: true },
        });

    const account = await tx.adminAccount.upsert({
      where: { userId: user.id },
      create: { userId: user.id, isActive: true },
      update: { isActive: true },
      select: { id: true, mfaEnrolledAt: true },
    });

    const { count: roleAdded } = await tx.adminUserRole.createMany({
      data: [{ adminAccountId: account.id, roleId: role.id }],
      skipDuplicates: true,
    });

    const enrollmentCode = account.mfaEnrolledAt
      ? null
      : await issueEnrollmentCode(tx, account.id, now);

    await tx.auditLog.create({
      data: {
        actorId: null,
        actorType: 'SYSTEM',
        action: 'admin.provision.grant',
        entity: 'AdminAccount',
        entityId: account.id,
        reason: input.reason.trim(),
        after: {
          role: role.key,
          email,
          createdUser: !existing,
          enrollmentCodeIssued: enrollmentCode !== null,
        },
      },
    });

    return {
      userId: user.id,
      adminAccountId: account.id,
      createdUser: !existing,
      roleAdded: roleAdded === 1,
      enrollmentCode,
    };
  });
}

export async function revokeAdminRole(
  db: Db,
  input: { email: string; roleKey: string; reason: string },
): Promise<{ removed: boolean }> {
  assertReason(input.reason);
  const account = await requireAdminAccount(db, input.email);
  return db.$transaction(async (tx) => {
    const { count } = await tx.adminUserRole.deleteMany({
      where: { adminAccountId: account.id, role: { key: input.roleKey } },
    });
    await tx.auditLog.create({
      data: {
        actorId: null,
        actorType: 'SYSTEM',
        action: 'admin.provision.revoke',
        entity: 'AdminAccount',
        entityId: account.id,
        reason: input.reason.trim(),
        before: { role: input.roleKey },
        after: { removed: count === 1 },
      },
    });
    return { removed: count === 1 };
  });
}

/** Lost or compromised authenticator: clears it, ends every session, and
 *  issues a fresh enrolment code. */
export async function resetAdminMfa(
  db: Db,
  input: { email: string; reason: string },
  now: Date = new Date(),
): Promise<{ enrollmentCode: string; sessionsEnded: number }> {
  assertReason(input.reason);
  const account = await requireAdminAccount(db, input.email);
  return db.$transaction(async (tx) => {
    await tx.adminAccount.update({
      where: { id: account.id },
      data: {
        mfaSecretEncrypted: null,
        mfaEnrolledAt: null,
        mfaLastUsedStep: null,
        mfaFailedAttempts: 0,
        mfaLockedUntil: null,
      },
    });
    const sessionsEnded = await revokeAllAdminSessions(
      tx,
      account.id,
      'MFA_RESET',
      now,
    );
    const enrollmentCode = await issueEnrollmentCode(tx, account.id, now);
    await tx.auditLog.create({
      data: {
        actorId: null,
        actorType: 'SYSTEM',
        action: 'admin.provision.reset_mfa',
        entity: 'AdminAccount',
        entityId: account.id,
        reason: input.reason.trim(),
        after: { sessionsEnded },
      },
    });
    return { enrollmentCode, sessionsEnded };
  });
}

/** Switches the account off and ends its sessions. Roles are kept, so
 *  re-granting restores the same access. */
export async function deactivateAdmin(
  db: Db,
  input: { email: string; reason: string },
  now: Date = new Date(),
): Promise<{ sessionsEnded: number }> {
  assertReason(input.reason);
  const account = await requireAdminAccount(db, input.email);
  return db.$transaction(async (tx) => {
    await tx.adminAccount.update({
      where: { id: account.id },
      data: { isActive: false },
    });
    const sessionsEnded = await revokeAllAdminSessions(
      tx,
      account.id,
      'DEACTIVATED',
      now,
    );
    await tx.auditLog.create({
      data: {
        actorId: null,
        actorType: 'SYSTEM',
        action: 'admin.provision.deactivate',
        entity: 'AdminAccount',
        entityId: account.id,
        reason: input.reason.trim(),
        after: { isActive: false, sessionsEnded },
      },
    });
    return { sessionsEnded };
  });
}

export async function listAdmins(db: Pick<PrismaClient, 'adminAccount'>) {
  const accounts = await db.adminAccount.findMany({
    select: {
      isActive: true,
      mfaEnrolledAt: true,
      lastLoginAt: true,
      user: { select: { email: true, role: true, status: true } },
      roles: { select: { role: { select: { key: true } } } },
    },
    orderBy: { createdAt: 'asc' },
  });
  return accounts.map((a) => ({
    email: a.user.email,
    userRole: a.user.role,
    userStatus: a.user.status,
    active: a.isActive,
    roles: a.roles.map((r) => r.role.key),
    authenticator: a.mfaEnrolledAt ? 'enrolled' : 'not enrolled',
    lastLoginAt: a.lastLoginAt?.toISOString() ?? null,
  }));
}

// ----------------------------------------------------------------------------

const USER_CHECK = {
  id: true,
  role: true,
  status: true,
  deletedAt: true,
  profile: { select: { id: true } },
} as const;

function assertPromotable(user: {
  id: string;
  role: string;
  status: string;
  deletedAt: Date | null;
  profile: { id: string } | null;
}): void {
  if (user.deletedAt) {
    throw new ProvisioningError(`User ${user.id} is deleted.`);
  }
  if (['SUSPENDED', 'BANNED', 'DEACTIVATED'].includes(user.status)) {
    throw new ProvisioningError(
      `User ${user.id} is ${user.status}; it cannot be made an admin.`,
    );
  }
  if (user.role === 'USER' && user.profile) {
    throw new ProvisioningError(
      `User ${user.id} is a member with a profile. Admins need a dedicated ` +
        'staff email and Firebase account.',
    );
  }
}

async function requireAdminAccount(db: Db, email: string) {
  const user = await db.user.findUnique({
    where: { email: email.trim().toLowerCase() },
    select: { adminAccount: { select: { id: true } } },
  });
  if (!user?.adminAccount) {
    throw new ProvisioningError(`No admin account for ${email}.`);
  }
  return user.adminAccount;
}

async function issueEnrollmentCode(
  tx: Pick<Prisma.TransactionClient, 'adminAccount'>,
  adminAccountId: string,
  now: Date,
): Promise<string> {
  const code = newEnrollmentCode();
  await tx.adminAccount.update({
    where: { id: adminAccountId },
    data: {
      mfaEnrollmentCodeHash: hashEnrollmentCode(code),
      mfaEnrollmentExpiresAt: new Date(
        now.getTime() + ADMIN_ENROLLMENT_CODE_TTL_MS,
      ),
      mfaFailedAttempts: 0,
      mfaLockedUntil: null,
    },
  });
  return code;
}

function assertReason(reason: string): void {
  if (typeof reason !== 'string' || reason.trim().length < 3) {
    throw new ProvisioningError('A reason (--reason "...") is required.');
  }
}
