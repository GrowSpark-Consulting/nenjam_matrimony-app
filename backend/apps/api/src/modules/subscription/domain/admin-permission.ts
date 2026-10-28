import { ForbiddenException } from '@nestjs/common';
import type { Prisma } from '../../../../../../libs/database/generated/client';

/**
 * Who may perform an administrative membership operation — checked INSIDE
 * the service, in the same transaction as the change, so no future
 * controller (or script) can skip it by forgetting a guard.
 *
 * Uses the permission format the admin seeder already writes to
 * `AdminAccount.permissions`: `{ <module>: [<action>, ...] }`, e.g.
 * `subscriptions: ['read', 'write', 'cancel']`. Membership uses:
 *
 *   subscriptions.write        grant, extend
 *   subscriptions.cancel       revoke
 *   membership.plans.write     publish a version, (de)activate, display
 *   membership.prices.write    set a duration's price / length / sale state
 *
 * The seeded admin already holds `subscriptions` but NOT `membership`, so
 * catalogue and price changes need an explicit grant — least privilege.
 */
export type AdminPermission =
  | { module: 'subscriptions'; action: 'write' | 'cancel' }
  | { module: 'membership'; action: 'plans.write' | 'prices.write' };

export async function assertAdminPermission(
  db: Prisma.TransactionClient,
  actorId: string,
  permission: AdminPermission,
): Promise<void> {
  const denied = () =>
    new ForbiddenException(
      `Not permitted: requires ${permission.module}.${permission.action}.`,
    );
  if (typeof actorId !== 'string' || actorId.length === 0) throw denied();

  const actor = await db.user.findUnique({
    where: { id: actorId },
    select: {
      role: true,
      status: true,
      deletedAt: true,
      adminAccount: { select: { permissions: true } },
    },
  });
  if (
    !actor ||
    actor.deletedAt !== null ||
    actor.status !== 'ACTIVE' ||
    actor.role !== 'ADMIN' ||
    !actor.adminAccount
  ) {
    throw denied();
  }
  const granted = (actor.adminAccount.permissions ?? {}) as Record<
    string,
    unknown
  >;
  const actions = granted[permission.module];
  if (!Array.isArray(actions) || !actions.includes(permission.action)) {
    throw denied();
  }
}
