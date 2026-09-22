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
 * Members hidden from discovery: premium members who switched on "Hide My
 * Profile". Stored in the `profileVisibleToPremiumOnly` column, which was
 * repurposed to mean "hide my profile" rather than adding a second, overlapping
 * flag.
 *
 * Hiding is a premium feature, so the flag alone is not enough: a member
 * without an active premium subscription stays visible even with it set. Used
 * as a `NOT` clause on the user relation by every discovery surface.
 */
export function hiddenFromDiscoveryWhere(now: Date): Prisma.UserWhereInput {
  return {
    profileVisibleToPremiumOnly: true,
    subscriptions: { some: activePremiumSubscriptionWhere(now) },
  };
}
