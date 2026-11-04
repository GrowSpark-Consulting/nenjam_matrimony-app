/**
 * Which sections the signed-in admin sees. This is presentation only — every
 * request is authorised again by the API, which returns 403 regardless of
 * what the menu shows.
 */
export interface NavItem {
  href: string;
  label: string;
  permission: string;
  group?: string;
}

export const NAV: readonly NavItem[] = [
  { href: '/', label: 'Overview', permission: 'dashboard.view' },
  { href: '/agents/', label: 'Agents', permission: 'agent.view' },
  {
    href: '/commissions/',
    label: 'Commissions',
    permission: 'commission.view',
    group: 'Agent program',
  },
  {
    href: '/payouts/',
    label: 'Payouts',
    permission: 'payout.view',
    group: 'Agent program',
  },
  {
    href: '/plans/',
    label: 'Plans',
    permission: 'plan.view',
    group: 'Membership',
  },
  {
    href: '/subscriptions/',
    label: 'Subscriptions',
    permission: 'subscription.view',
    group: 'Membership',
  },
  { href: '/audit/', label: 'Audit log', permission: 'audit.view', group: 'Platform' },
  {
    href: '/roles/',
    label: 'Roles & permissions',
    permission: 'rbac.manage',
    group: 'Platform',
  },
];

export function can(
  permissions: readonly string[] | undefined,
  permission: string,
): boolean {
  return !!permissions?.includes(permission);
}

export function visibleNav(permissions: readonly string[]): NavItem[] {
  return NAV.filter((item) => can(permissions, item.permission));
}

/** Where to land after sign-in: the first section this admin may open. */
export function homeFor(permissions: readonly string[]): string | null {
  return visibleNav(permissions)[0]?.href ?? null;
}
