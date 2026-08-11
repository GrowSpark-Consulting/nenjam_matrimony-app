import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  Prisma,
  Shortlist,
} from '../../../../../../libs/database/generated/client';
import { FEED_PROFILE_SELECT, type FeedProfileRow } from './feed.repository';
import { notBlockedWith } from '../../blocks/filters/block-exclusion.builder';

/** A Prisma client that is either the base service or a transaction client, so
 *  a shortlist add can commit atomically with its notification. */
export type PrismaClientLike = PrismaService | Prisma.TransactionClient;

@Injectable()
export class ShortlistRepository {
  constructor(private readonly prisma: PrismaService) {}

  async exists(userId: string, targetUserId: string): Promise<boolean> {
    const count = await this.prisma.shortlist.count({
      where: { userId, targetUserId },
    });
    return count > 0;
  }

  /** Whether the target user is a live account (exists and not soft-deleted). */
  async isTargetAvailable(targetUserId: string): Promise<boolean> {
    const user = await this.prisma.user.findUnique({
      where: { id: targetUserId },
      select: { deletedAt: true },
    });
    return Boolean(user) && !user!.deletedAt;
  }

  async isBlockedBetween(a: string, b: string): Promise<boolean> {
    const count = await this.prisma.userBlock.count({
      where: {
        OR: [
          { blockerId: a, blockedUserId: b },
          { blockerId: b, blockedUserId: a },
        ],
      },
    });
    return count > 0;
  }

  create(
    client: PrismaClientLike,
    userId: string,
    targetUserId: string,
  ): Promise<Shortlist> {
    return client.shortlist.create({ data: { userId, targetUserId } });
  }

  /** Idempotent remove — returns rows deleted (0 = wasn't shortlisted). */
  async remove(userId: string, targetUserId: string): Promise<number> {
    const result = await this.prisma.shortlist.deleteMany({
      where: { userId, targetUserId },
    });
    return result.count;
  }

  /** Newest-first, excluding rows whose TARGET has a mutual block with
   *  [userId] — a block hides prior shortlist entries from list views, not
   *  just future adds (mirrors Discover/Search's block exclusion). */
  list(
    userId: string,
    skip: number,
    take: number,
  ): Promise<[Shortlist[], number]> {
    const where: Prisma.ShortlistWhereInput = {
      userId,
      targetUser: { is: notBlockedWith(userId) },
    };
    // Concurrent, not `$transaction([...])`: at READ COMMITTED (this database's
    // default) a transaction gives page/count no shared snapshot anyway, and it
    // costs a sequential BEGIN/COMMIT round trip either side — measured at
    // 307ms vs 74ms for the same two queries.
    return Promise.all([
      this.prisma.shortlist.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take,
      }),
      this.prisma.shortlist.count({ where }),
    ]);
  }

  findFeedProfilesByUserIds(userIds: string[]): Promise<FeedProfileRow[]> {
    if (userIds.length === 0) return Promise.resolve([]);
    return this.prisma.userProfile.findMany({
      where: { userId: { in: userIds } },
      select: FEED_PROFILE_SELECT,
    });
  }
}
