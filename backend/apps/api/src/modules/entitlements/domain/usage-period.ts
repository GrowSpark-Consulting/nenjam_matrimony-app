import type { QuotaPeriod } from '../catalog/feature-catalog';

/**
 * Usage-period boundaries — the one definition of "today", "this month" and
 * "this plan" for every metered feature, so a counter, its reset time and the
 * number shown to the member can never disagree.
 *
 * Days and months follow the Indian calendar (IST, UTC+05:30): a Free member
 * in Chennai gets new daily allowances at their midnight, not at 05:30. India
 * observes no daylight saving, so a fixed offset is exact.
 *
 * A SUBSCRIPTION period is the subscription's own term, keyed by its id, so a
 * per-plan pool (contact unlocks) belongs to the purchase that granted it and
 * a new purchase starts a fresh pool. A member with no subscription draws on a
 * single lifetime "free" pool.
 */

const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;

export interface UsagePeriod {
  /** Stored in membership_usage_counters.period_key. */
  key: string;
  /** When the next period starts; null for the lifetime free pool. */
  endsAt: Date | null;
}

export interface PeriodSubscription {
  id: string;
  endDate: Date;
}

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

/** The UTC instant of IST midnight at the start of the given IST date. */
function istMidnightUtc(year: number, monthIndex: number, day: number): Date {
  return new Date(Date.UTC(year, monthIndex, day) - IST_OFFSET_MS);
}

export function usagePeriodFor(
  period: QuotaPeriod,
  now: Date,
  subscription: PeriodSubscription | null,
): UsagePeriod {
  // The IST wall-clock date, read off a UTC-shifted instant.
  const ist = new Date(now.getTime() + IST_OFFSET_MS);
  const year = ist.getUTCFullYear();
  const month = ist.getUTCMonth();
  const day = ist.getUTCDate();

  switch (period) {
    case 'DAY':
      return {
        key: `D:${year}-${pad(month + 1)}-${pad(day)}`,
        endsAt: istMidnightUtc(year, month, day + 1),
      };
    case 'MONTH':
      return {
        key: `M:${year}-${pad(month + 1)}`,
        endsAt: istMidnightUtc(year, month + 1, 1),
      };
    case 'SUBSCRIPTION':
      return subscription
        ? { key: `S:${subscription.id}`, endsAt: subscription.endDate }
        : { key: 'S:free', endsAt: null };
  }
}
