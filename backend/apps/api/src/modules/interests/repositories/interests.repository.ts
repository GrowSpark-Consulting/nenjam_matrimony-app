import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  ExpressInterest,
  InterestStatus,
  Prisma,
  UserStatus,
} from '../../../../../../libs/database/generated/client';
import {
  FEED_PROFILE_SELECT,
  type FeedProfileRow,
} from '../../matches/repositories/feed.repository';
import { notBlockedWith } from '../../blocks/filters/block-exclusion.builder';

/** A Prisma client that is either the base service or a transaction client, so
 *  interest writes can run inside the service's `$transaction`. */
export type PrismaClientLike = PrismaService | Prisma.TransactionClient;

/** Receiver eligibility snapshot for the send-interest business rules. */
export interface ReceiverState {
  id: string;
  deletedAt: Date | null;
  status: UserStatus;
}

@Injectable()
export class InterestsRepository {
  constructor(private readonly prisma: PrismaService) {}

  // ── validation reads (send business rules) ────────────────────────────────

  findReceiverState(receiverId: string): Promise<ReceiverState | null> {
    return this.prisma.user.findUnique({
      where: { id: receiverId },
      select: { id: true, deletedAt: true, status: true },
    });
  }

  /** True if either user has blocked the other (block is directional in the
   *  table but mutually disqualifying for interest). */
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

  async isProfileComplete(userId: string): Promise<boolean> {
    const profile = await this.prisma.userProfile.findUnique({
      where: { userId },
      select: { isProfileComplete: true },
    });
    return profile?.isProfileComplete ?? false;
  }

  // ── interest records ──────────────────────────────────────────────────────

  findByPair(
    client: PrismaClientLike,
    senderId: string,
    receiverId: string,
  ): Promise<ExpressInterest | null> {
    return client.expressInterest.findUnique({
      where: { senderId_receiverId: { senderId, receiverId } },
    });
  }

  /** An active (PENDING/ACCEPTED) interest in the OPPOSITE direction — used to
   *  block A→B when B→A already exists. */
  findReverseActive(
    senderId: string,
    receiverId: string,
  ): Promise<ExpressInterest | null> {
    return this.prisma.expressInterest.findFirst({
      where: {
        senderId: receiverId,
        receiverId: senderId,
        status: { in: ['PENDING', 'ACCEPTED'] },
      },
    });
  }

  findById(id: string): Promise<ExpressInterest | null> {
    return this.prisma.expressInterest.findUnique({ where: { id } });
  }

  create(
    client: PrismaClientLike,
    senderId: string,
    receiverId: string,
  ): Promise<ExpressInterest> {
    return client.expressInterest.create({
      data: { senderId, receiverId, status: 'PENDING' },
    });
  }

  /** Re-send a previously declined interest — back to PENDING, response cleared. */
  resetToPending(
    client: PrismaClientLike,
    id: string,
  ): Promise<ExpressInterest> {
    return client.expressInterest.update({
      where: { id },
      data: { status: 'PENDING', respondedAt: null },
    });
  }

  /** Race-safe respond: only transitions a still-PENDING record, so two
   *  concurrent accepts can't both win. Returns rows changed (0 = already
   *  responded by a competing request). */
  async respondIfPending(
    client: PrismaClientLike,
    id: string,
    status: Extract<InterestStatus, 'ACCEPTED' | 'DECLINED'>,
  ): Promise<number> {
    const result = await client.expressInterest.updateMany({
      where: { id, status: 'PENDING' },
      data: { status, respondedAt: new Date() },
    });
    return result.count;
  }

  /** Race-safe withdraw: deletes only the caller's own still-PENDING sent
   *  interest (ownership + status enforced in the WHERE). Returns rows removed
   *  (0 = not the caller's / not pending / already withdrawn). */
  async deletePendingSent(senderId: string, id: string): Promise<number> {
    const result = await this.prisma.expressInterest.deleteMany({
      where: { id, senderId, status: 'PENDING' },
    });
    return result.count;
  }

  // ── paginated lists ───────────────────────────────────────────────────────

  /** Newest-first, excluding rows whose SENDER has a mutual block with
   *  [userId] — a block hides prior interests from list views, not just future
   *  sends (mirrors Discover/Search's block exclusion). */
  listReceived(
    userId: string,
    skip: number,
    take: number,
  ): Promise<[ExpressInterest[], number]> {
    const where: Prisma.ExpressInterestWhereInput = {
      receiverId: userId,
      sender: { is: notBlockedWith(userId) },
    };
    return this.prisma.$transaction([
      this.prisma.expressInterest.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take,
      }),
      this.prisma.expressInterest.count({ where }),
    ]);
  }

  /** Newest-first, excluding rows whose RECEIVER has a mutual block with
   *  [userId] — see [listReceived]. */
  listSent(
    userId: string,
    skip: number,
    take: number,
  ): Promise<[ExpressInterest[], number]> {
    const where: Prisma.ExpressInterestWhereInput = {
      senderId: userId,
      receiver: { is: notBlockedWith(userId) },
    };
    return this.prisma.$transaction([
      this.prisma.expressInterest.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take,
      }),
      this.prisma.expressInterest.count({ where }),
    ]);
  }

  /** Public profile cards for a set of users, in the exact shape
   *  ProfileFeedMapper consumes — reuses the feed's column selection so the
   *  interest/shortlist cards are identical to Discover cards. */
  findFeedProfilesByUserIds(userIds: string[]): Promise<FeedProfileRow[]> {
    if (userIds.length === 0) return Promise.resolve([]);
    return this.prisma.userProfile.findMany({
      where: { userId: { in: userIds } },
      select: FEED_PROFILE_SELECT,
    });
  }
}
