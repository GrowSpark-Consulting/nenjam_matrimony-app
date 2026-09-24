import { hiddenFromDiscoveryWhere } from '@app/database';
import type {
  Prisma,
  Gender,
} from '../../../../../../libs/database/generated/client';

/**
 * Account states that are never shown to anyone. A denylist rather than an
 * ACTIVE allowlist on purpose: there is no verification flow in this app that
 * ever promotes a member out of PENDING_VERIFICATION, so requiring ACTIVE
 * would hide every real signup from every surface. Revisit once one exists.
 */
export const INELIGIBLE_ACCOUNT_STATUSES = [
  'SUSPENDED',
  'DEACTIVATED',
  'BANNED',
] as const;

export interface EligibilityParams {
  currentUserId: string;
  /** The caller's own gender. Null (no finalized profile) fails closed. */
  myGender: Gender | null;
  /** The instant subscription expiry is judged against. Defaults to the
   *  current time; passed explicitly only where one request builds several
   *  WHEREs, or by tests that need a stable filter. */
  now?: Date;
}

/**
 * The hard "never show this person" rules, in one place.
 *
 * Every surface that lists other members — Discover (every fallback tier),
 * Search and Near Me — takes its eligibility from here and nowhere else. These
 * rules REMOVE a candidate; nothing downstream (preference filtering, scoring,
 * ranking, fallback relaxation) can put one back, because each of those only
 * ever narrows or reorders what this returns.
 *
 * This replaces two copies that had drifted apart: `buildFeedWhere` carried
 * status and blocks but not declined interests, while `withSafetyExclusions`
 * carried all three but was only applied from fallback Tier 2 onward and on
 * Near Me. So someone who had declined you could reach you in Tier 1 and in
 * Search but not in a fallback tier — the same person, visible or not
 * depending on how many other matches you happened to have.
 *
 * Rules:
 *  - never the caller themselves;
 *  - only finalized profiles (`isProfileComplete`);
 *  - never a soft-deleted account;
 *  - never a SUSPENDED / DEACTIVATED / BANNED account;
 *  - never across a block, in either direction;
 *  - never across a declined interest, in either direction;
 *  - never a member who chose "Hide My Profile" (see hiddenFromDiscoveryWhere
 *    — temporarily any member; premium-only again once
 *    ALLOW_FREE_PRIVACY_CONTROLS is switched off). Relationship surfaces (interests, chat,
 *    shortlist, profile views, blocks) don't go through this builder, so an
 *    existing relationship keeps working after someone hides;
 *  - opposite gender only — and with the caller's own gender unknown, nobody
 *    (fail closed rather than return a mixed-gender list).
 *
 * The account rules share one `user.is` relation filter so the database
 * resolves the user row once for all of them — including the hidden-profile
 * rule, whose subscription check is an EXISTS inside the same query rather
 * than a lookup per candidate.
 */
export function buildEligibilityConditions({
  currentUserId,
  myGender,
  now = new Date(),
}: EligibilityParams): Prisma.UserProfileWhereInput[] {
  return [
    { userId: { not: currentUserId } },
    { isProfileComplete: true },
    {
      user: {
        is: {
          deletedAt: null,
          status: { notIn: [...INELIGIBLE_ACCOUNT_STATUSES] },
          NOT: [
            // They blocked me / I blocked them.
            { blocksMade: { some: { blockedUserId: currentUserId } } },
            { blocksReceived: { some: { blockerId: currentUserId } } },
            // I asked and they declined / they asked and I declined.
            {
              receivedInterests: {
                some: { senderId: currentUserId, status: 'DECLINED' },
              },
            },
            {
              sentInterests: {
                some: { receiverId: currentUserId, status: 'DECLINED' },
              },
            },
            // A member who hid their profile.
            hiddenFromDiscoveryWhere(now),
          ],
        },
      },
    },
    genderCondition(myGender),
  ];
}

/** [buildEligibilityConditions] as a standalone WHERE. */
export function buildEligibilityWhere(
  params: EligibilityParams,
): Prisma.UserProfileWhereInput {
  return { AND: buildEligibilityConditions(params) };
}

function genderCondition(
  myGender: Gender | null,
): Prisma.UserProfileWhereInput {
  if (myGender === 'MALE') return { gender: 'FEMALE' };
  if (myGender === 'FEMALE') return { gender: 'MALE' };
  // An empty `in` matches nothing — the mandatory opposite-gender rule cannot
  // be anchored, so no candidate qualifies.
  return { gender: { in: [] } };
}
