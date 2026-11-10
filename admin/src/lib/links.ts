/**
 * Addresses that open a list page already filtered (used by the Overview),
 * and reading those filters back on the list page. Only known values are
 * accepted from the address; anything else falls back to the page default.
 */

type Params = { get(name: string): string | null };

function withQuery(path: string, query: Record<string, string | undefined>): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value) params.set(key, value);
  }
  const qs = params.toString();
  return qs ? `${path}?${qs}` : path;
}

export const SUBSCRIPTION_STATUSES = ['ACTIVE', 'PENDING', 'EXPIRED', 'CANCELLED'] as const;
export const SUBSCRIPTION_PLANS = ['GOLD', 'PLATINUM', 'SILVER'] as const;

export function subscriptionsHref(filter: { status?: string; plan?: string } = {}): string {
  return withQuery('/subscriptions/', { status: filter.status, plan: filter.plan });
}

export function agentsHref(status?: string): string {
  return withQuery('/agents/', { status });
}

export const USER_STATUSES = [
  'ACTIVE',
  'BLOCKED',
  'SUSPENDED',
  'PENDING_VERIFICATION',
  'DEACTIVATED',
  'BANNED',
] as const;

export function usersHref(filter: { status?: string; search?: string } = {}): string {
  return withQuery('/users/', { status: filter.status, search: filter.search });
}

/** [key] from the address if it is one of [allowed], otherwise [fallback]. */
export function readFilter(
  params: Params | null | undefined,
  key: string,
  allowed: readonly string[],
  fallback = '',
): string {
  const value = params?.get(key) ?? null;
  return value !== null && allowed.includes(value) ? value : fallback;
}
