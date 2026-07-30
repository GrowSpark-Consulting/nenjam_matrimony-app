import type { Prisma } from '../../../../../../libs/database/generated/client';

/**
 * A Prisma `User`-relation WHERE fragment excluding anyone who has blocked
 * [userId] or whom [userId] has blocked. Mirrors the inline block exclusion in
 * `matches/filters/partner-preference-where.builder.ts` (Discover/Search) so
 * Interests and Shortlist lists apply the identical mutual-block rule against
 * whichever relation on the row points at the counterpart (e.g. `sender`,
 * `receiver`, `targetUser`).
 */
export function notBlockedWith(userId: string): Prisma.UserWhereInput {
  return {
    NOT: [
      { blocksMade: { some: { blockedUserId: userId } } },
      { blocksReceived: { some: { blockerId: userId } } },
    ],
  };
}
