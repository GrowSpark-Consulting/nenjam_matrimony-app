import type { Prisma } from '../../generated/client';

/**
 * What "has an active premium subscription" means, as a Prisma filter — the
 * single definition every query and service shares, so the premium rule can't
 * drift between the entitlement check, the discovery WHERE and the photo gate.
 *
 * A subscription grants premium only while ALL of these hold:
 *  - `status` is ACTIVE (never PENDING, EXPIRED or CANCELLED);
 *  - it has started (`startDate <= now`) and not yet ended (`endDate > now`),
 *    so a row nobody flipped to EXPIRED still stops counting on its end date;
 *  - it is for a paid plan — an ACTIVE subscription to the FREE plan is not
 *    premium.
 *
 * Takes `now` rather than reading the clock so a caller building several
 * filters for one request evaluates them all against the same instant.
 *
 * NOTE: nothing creates UserSubscription rows yet — checkout, the Razorpay
 * webhook and the subscription module are unimplemented stubs — so today this
 * matches nobody and every member is treated as non-premium.
 */
export function activePremiumSubscriptionWhere(
  now: Date,
): Prisma.UserSubscriptionWhereInput {
  return {
    status: 'ACTIVE',
    startDate: { lte: now },
    endDate: { gt: now },
    plan: { name: { not: 'FREE' } },
  };
}

/**
 * TODO(premium): both privacy controls — "Hide My Profile" and "Hide Photos
 * from Non-Connections" — are temporarily available to all users; restore
 * premium gating when subscriptions/checkout are live — set this back to
 * `false`. It is the ONLY switch: the discovery rule below, the photo gate
 * (`arePhotosHidden`) and the `PATCH /settings/privacy` check all read it, so
 * enforcement and the API can never disagree. Nothing else premium reads it.
 *
 * A code constant rather than an env var on purpose: the rule is shared by
 * the API and the separately deployed scheduler (weekly digest), and an env
 * var set on one Railway service but not the other would hide a member from
 * Discover yet still mail them out.
 */
export const ALLOW_FREE_PRIVACY_CONTROLS = true;

/**
 * Members hidden from discovery: members who switched on "Hide My Profile".
 * Stored in the `profileVisibleToPremiumOnly` column, which was repurposed to
 * mean "hide my profile" rather than adding a second, overlapping flag.
 *
 * While [ALLOW_FREE_PRIVACY_CONTROLS] is on, the flag alone hides anyone. With it
 * off, hiding is a premium feature: a member without an active premium
 * subscription stays visible even with the flag set. Used as a `NOT` clause on
 * the user relation by every discovery surface.
 */
export function hiddenFromDiscoveryWhere(
  now: Date,
  allowFreePrivacy: boolean = ALLOW_FREE_PRIVACY_CONTROLS,
): Prisma.UserWhereInput {
  if (allowFreePrivacy) return { profileVisibleToPremiumOnly: true };
  return {
    profileVisibleToPremiumOnly: true,
    subscriptions: { some: activePremiumSubscriptionWhere(now) },
  };
}
