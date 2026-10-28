/**
 * Every permission an admin route or service can require, as
 * `<resource>.<action>` (Nenjam Admin Architecture v3, section 13).
 *
 * The database holds the same keys — seeded by migrations, starting with
 * `20261028070845_admin_rbac_foundation` — so roles can bundle them. This list
 * is what code checks against, so a mistyped key in `@RequirePermissions`
 * fails to compile instead of silently denying everyone. A new key needs both
 * an entry here and an INSERT in a new migration (`permissions.spec.ts`
 * compares the two, sensitivity included).
 */
export const PERMISSIONS = [
  // dashboard and members
  'dashboard.view',
  'finance.view',
  'member.view',
  'member.pii.reveal',
  'member.suspend',
  'member.session.revoke',
  'verification.decide',
  'photo.moderate',
  'report.resolve',
  'support.ticket.respond',
  'support.ticket.assign',
  // subscriptions, plans, payments
  'subscription.view',
  'subscription.extend',
  'subscription.cancel',
  'subscription.grant',
  'plan.view',
  'plan.edit',
  'plan.publish',
  'feature.registry.edit',
  'coupon.manage',
  'payment.view',
  'payment.reconcile',
  'payment.record_offline',
  'refund.request',
  'refund.approve',
  // Agent / Partner Program
  'agent.view',
  'agent.approve',
  'agent.manage',
  'agent.payout_details.verify',
  'agent.pii.reveal',
  'attribution.view',
  'attribution.override',
  'commission.view',
  'commission.approve',
  'commission.cancel',
  'commission.override',
  'commission.policy.edit',
  'commission.adjust',
  'payout.view',
  'payout.execute',
  // platform
  'report.view',
  'report.export',
  'flag.toggle',
  'config.edit',
  'rbac.manage',
  'audit.view',
  'system.view',
  'system.job.retry',
] as const;

export type PermissionKey = (typeof PERMISSIONS)[number];

/**
 * Keys that also need a recent second-factor check (step-up) on the session
 * using them — the PDF's money, personal-data and access-control actions.
 */
export const SENSITIVE_PERMISSIONS: ReadonlySet<PermissionKey> =
  new Set<PermissionKey>([
    'member.pii.reveal',
    'agent.pii.reveal',
    'refund.approve',
    'payout.execute',
    'rbac.manage',
  ]);

export function isPermissionKey(value: string): value is PermissionKey {
  return (PERMISSIONS as readonly string[]).includes(value);
}
