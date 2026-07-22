import type { Prisma } from '../../../../../../libs/database/generated/client';

/**
 * Baseline "never show this person" exclusions layered on top of a fallback
 * tier's WHERE — blocked/rejected/inactive users. Deliberately NOT part of
 * [buildFeedWhere]/Tier 1: Tier 1 must stay byte-for-byte the existing
 * recommendation engine, unmodified. As the tiers relax and fewer real
 * preference signals remain, these are what keep the loosest tiers (esp.
 * Tier 10 — gender-only) from ever surfacing someone who blocked the caller,
 * was blocked by the caller, mutually declined an interest, or whose account
 * isn't ACTIVE.
 *
 * NOTE: "hidden users" (from the spec) has no corresponding field on `User`/
 * `UserProfile` in the current schema — there's no visibility toggle to
 * filter on. Not implemented; flagged rather than guessed at with an invented
 * column.
 */
export function withSafetyExclusions(
  where: Prisma.UserProfileWhereInput,
  currentUserId: string,
): Prisma.UserProfileWhereInput {
  const existing = Array.isArray(where.AND)
    ? (where.AND as Prisma.UserProfileWhereInput[])
    : where.AND
      ? [where.AND as Prisma.UserProfileWhereInput]
      : [];

  return {
    AND: [
      ...existing,
      // Must match buildFeedWhere's status check exactly (denylist, not an
      // ACTIVE allowlist): there is no verification flow anywhere in this app
      // that ever promotes a user out of PENDING_VERIFICATION, so requiring
      // ACTIVE here would silently re-hide every real signup from every
      // fallback tier (2-10) even though Tier 1 already lets them through.
      { user: { is: { status: { notIn: ['SUSPENDED', 'DEACTIVATED', 'BANNED'] } } } },
      // Neither direction of a block: candidate blocked me, or I blocked them.
      {
        user: {
          is: { blocksMade: { none: { blockedUserId: currentUserId } } },
        },
      },
      {
        user: {
          is: { blocksReceived: { none: { blockerId: currentUserId } } },
        },
      },
      // Neither direction of a declined interest: I asked and they said no,
      // or they asked and I said no.
      {
        user: {
          is: {
            receivedInterests: {
              none: { senderId: currentUserId, status: 'DECLINED' },
            },
          },
        },
      },
      {
        user: {
          is: {
            sentInterests: {
              none: { receiverId: currentUserId, status: 'DECLINED' },
            },
          },
        },
      },
    ],
  };
}
