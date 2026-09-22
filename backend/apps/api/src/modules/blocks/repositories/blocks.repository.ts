import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type { UserBlock } from '../../../../../../libs/database/generated/client';
import {
  feedProfileSelectFor,
  type FeedProfileRow,
} from '../../matches/repositories/feed.repository';

@Injectable()
export class BlocksRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** Whether the target user is a live account (exists and not soft-deleted). */
  async isTargetAvailable(targetUserId: string): Promise<boolean> {
    const user = await this.prisma.user.findUnique({
      where: { id: targetUserId },
      select: { deletedAt: true },
    });
    return Boolean(user) && !user!.deletedAt;
  }

  /** Idempotent: re-blocking an already-blocked user is a no-op upsert. */
  block(blockerId: string, blockedUserId: string): Promise<{ id: string }> {
    return this.prisma.userBlock.upsert({
      where: { blockerId_blockedUserId: { blockerId, blockedUserId } },
      create: { blockerId, blockedUserId },
      update: {},
      select: { id: true },
    });
  }

  /** Idempotent: unblocking a user who isn't blocked is a no-op. */
  async unblock(blockerId: string, blockedUserId: string): Promise<void> {
    await this.prisma.userBlock.deleteMany({
      where: { blockerId, blockedUserId },
    });
  }

  /** Newest-first page of members [userId] has blocked. */
  listBlocked(
    userId: string,
    skip: number,
    take: number,
  ): Promise<[UserBlock[], number]> {
    const where = { blockerId: userId };
    // Concurrent, not `$transaction([...])`: at READ COMMITTED (this database's
    // default) a transaction gives page/count no shared snapshot anyway, and it
    // costs a sequential BEGIN/COMMIT round trip either side — measured at
    // 307ms vs 74ms for the same two queries.
    return Promise.all([
      this.prisma.userBlock.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take,
      }),
      this.prisma.userBlock.count({ where }),
    ]);
  }

  /** Public profile cards for a set of users, in the exact shape
   *  ProfileFeedMapper consumes — reuses the feed's column selection so
   *  blocked-member cards render identically to Discover cards. */
  findFeedProfilesByUserIds(
    userIds: string[],
    viewerId: string,
  ): Promise<FeedProfileRow[]> {
    if (userIds.length === 0) return Promise.resolve([]);
    return this.prisma.userProfile.findMany({
      where: { userId: { in: userIds } },
      select: feedProfileSelectFor(viewerId),
    });
  }
}
