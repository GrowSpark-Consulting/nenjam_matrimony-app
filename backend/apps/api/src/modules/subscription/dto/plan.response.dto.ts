import type {
  SubscriptionPlanName,
  SubscriptionSource,
  SubscriptionStatus,
  PaymentStatus,
} from '../../../../../../libs/database/generated/client';
import type {
  CapFeatureKey,
  EntitlementMap,
  FeatureKey,
  FeatureKind,
  FeatureSection,
  QuotaPeriod,
} from '../../entitlements/catalog/feature-catalog';
import type { PurchaseKind } from '../domain/schedule';

/** One feature's metadata, so a client can render any plan's map without
 *  hardcoding what the ids mean. */
export interface FeatureDescriptorDto {
  key: FeatureKey;
  kind: FeatureKind;
  section: FeatureSection;
  label: string;
  period?: QuotaPeriod;
  levels?: readonly string[];
  requiredOnEveryPlan?: boolean;
}

export interface PlanDurationDto {
  months: number;
  durationDays: number;
  bonusDays: number;
  priceInPaise: number;
  currency: string;
}

export interface PlanDto {
  code: SubscriptionPlanName;
  name: string;
  description: string | null;
  tier: number;
  isFree: boolean;
  /** The durations on sale now (priced and active); empty when none is. */
  durations: PlanDurationDto[];
  /** What the plan grants to a member who buys (or, for Free, has) it now. */
  entitlements: EntitlementMap;
  version: number;
}

/** GET /membership/plans */
export interface PlanCatalogResponseDto {
  plans: PlanDto[];
  features: FeatureDescriptorDto[];
  /** False until Razorpay is configured — nothing can be bought yet. */
  checkoutAvailable: boolean;
}

export interface QuotaUsageDto {
  feature: FeatureKey;
  period: QuotaPeriod;
  used: number;
  limit: number | null;
  remaining: number | null;
  fairUse: boolean;
  resetsAt: string | null;
}

/** GET /membership/me */
export interface MyMembershipResponseDto {
  plan: { code: SubscriptionPlanName; name: string; tier: number } | null;
  /** SUBSCRIPTION or FREE normally. LEGACY: a subscription from before plan
   *  versions is in force — no limits apply and entitlements is null.
   *  UNAVAILABLE: the catalogue couldn't be read — same (fail open). */
  source: 'SUBSCRIPTION' | 'FREE' | 'LEGACY' | 'UNAVAILABLE';
  /** The plan version whose terms apply (null for LEGACY / UNAVAILABLE). */
  planVersion: number | null;
  subscription: {
    id: string;
    planCode: SubscriptionPlanName;
    /** Always ACTIVE here — only a subscription in force is "current". */
    status: 'ACTIVE';
    startDate: string;
    endDate: string;
    months: number | null;
    autoRenew: boolean;
    cancelledAt: string | null;
    source: SubscriptionSource;
  } | null;
  /** Paid plans already bought that start later (renewals, downgrades). */
  scheduled: Array<{
    id: string;
    planCode: SubscriptionPlanName;
    planName: string;
    startDate: string;
    endDate: string;
  }>;
  entitlements: EntitlementMap | null;
  usage: QuotaUsageDto[];
  /**
   * Every plan length on sale now, with what buying it would mean for THIS
   * member: UPGRADE (starts now), RENEWAL / DOWNGRADE (queued behind what
   * they hold), or NEW. `startsAt`/`endsAt` follow the exact rule activation
   * uses. Empty while nothing is priced and on sale.
   */
  purchaseOptions: PurchaseOptionDto[];
  /**
   * For every cap feature (`profile.photos`, `shortlist.profiles`, …), the
   * cap the backend ACTUALLY applies right now — use this, not
   * `entitlements`, to stop an upload/add before it is refused. Under
   * `enforce` it is the plan's limit; otherwise the pre-membership cap
   * (photos: 6) or null (no cap).
   */
  effectiveCaps: Record<CapFeatureKey, number | null>;
  /** False until Razorpay is configured: purchaseOptions can't be bought. */
  checkoutAvailable: boolean;
  /** Whether limits are enforced right now (MEMBERSHIP_ENFORCEMENT_MODE). */
  limitsEnforced: boolean;
}

export interface PurchaseOptionDto {
  planCode: SubscriptionPlanName;
  planName: string;
  months: number;
  priceInPaise: number;
  currency: string;
  kind: PurchaseKind;
  startsAt: string;
  endsAt: string;
}

/** GET /membership/history — one entry per purchase or grant. */
export interface SubscriptionHistoryItemDto {
  id: string;
  plan: { code: SubscriptionPlanName; name: string };
  months: number | null;
  status: SubscriptionStatus;
  source: SubscriptionSource;
  startDate: string;
  endDate: string;
  priceInPaise: number | null;
  currency: string | null;
  activatedAt: string | null;
  cancelledAt: string | null;
  cancellationReason: string | null;
  createdAt: string;
  payments: Array<{
    id: string;
    orderId: string | null;
    paymentId: string | null;
    amountInPaise: number;
    currency: string;
    status: PaymentStatus;
    paidAt: string | null;
    refundedAmount: number;
    refundedAt: string | null;
  }>;
}

/** POST /membership/subscription/cancel */
export interface CancelSubscriptionResponseDto {
  cancelled: number;
  /** Paid access continues until then. */
  accessUntil: string;
}
