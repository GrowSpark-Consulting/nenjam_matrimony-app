import type {
  SubscriptionPlanName,
  SubscriptionSource,
} from '../../../../../../libs/database/generated/client';
import type { EntitlementMap } from '../catalog/feature-catalog';

/** One purchasable length of a plan, as currently priced. */
export interface CatalogDuration {
  id: string;
  months: number;
  durationDays: number;
  bonusDays: number;
  /** Paise; null = not priced yet (never purchasable). */
  priceInPaise: number | null;
  currency: string;
  isActive: boolean;
  displayOrder: number;
}

/** One immutable entitlement snapshot of a plan. */
export interface CatalogVersion {
  id: string;
  planId: string;
  version: number;
  effectiveFrom: Date;
  entitlements: EntitlementMap;
  /** Validation problems found when the stored row was read (logged). */
  problems: string[];
}

export interface CatalogPlan {
  id: string;
  code: SubscriptionPlanName;
  name: string;
  description: string | null;
  tier: number;
  displayOrder: number;
  isActive: boolean;
  durations: CatalogDuration[];
  /** Newest effective first (effectiveFrom desc, then version desc). */
  versions: CatalogVersion[];
}

export interface PlanCatalog {
  /** Every plan, active or not, in display order. */
  plans: CatalogPlan[];
  loadedAt: Date;
}

/** The subscription currently granting a member their plan. */
export interface CurrentSubscription {
  id: string;
  planCode: SubscriptionPlanName;
  status: 'ACTIVE';
  startDate: Date;
  endDate: Date;
  /** Plan length bought, when known (drives perMonths scaling). */
  months: number | null;
  autoRenew: boolean;
  cancelledAt: Date | null;
  source: SubscriptionSource;
}

/**
 * Who a member is, membership-wise, at one instant.
 *
 * `source`:
 *  - `SUBSCRIPTION` — a paid (or granted) subscription is in force.
 *  - `FREE` — no subscription in force: the Free plan's current version.
 *  - `LEGACY` — a subscription from before plan versions (no pinned
 *    version) is in force. What it was sold as isn't recorded, so it is
 *    never reinterpreted under today's terms: entitlements are null and no
 *    limit applies (see MembershipService.resolve).
 *  - `UNAVAILABLE` — the catalogue itself could not be read (missing Free
 *    plan, database error). Entitlements are null and every check FAILS
 *    OPEN to pre-membership behaviour: a broken catalogue must never lock
 *    members out of the app.
 */
export interface ResolvedMembership {
  userId: string;
  source: 'SUBSCRIPTION' | 'FREE' | 'LEGACY' | 'UNAVAILABLE';
  plan: {
    id: string;
    code: SubscriptionPlanName;
    name: string;
    tier: number;
  } | null;
  planVersion: { id: string; version: number } | null;
  subscription: CurrentSubscription | null;
  entitlements: EntitlementMap | null;
  resolvedAt: Date;
}
