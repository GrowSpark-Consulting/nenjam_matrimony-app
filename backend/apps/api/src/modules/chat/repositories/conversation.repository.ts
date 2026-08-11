import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  ChatMessage,
  ChatParticipantState,
  ChatRoom,
  Prisma,
} from '../../../../../../libs/database/generated/client';

/** The per-user room-state fields a caller may patch. */
export interface ChatStatePatch {
  isPinned?: boolean;
  isMuted?: boolean;
  isArchived?: boolean;
  markUnread?: boolean;
  lastReadMessageId?: string | null;
  lastReadAt?: Date | null;
  deletedUntil?: Date | null;
  customNotification?: string | null;
}
import {
  FEED_PROFILE_SELECT,
  type FeedProfileRow,
} from '../../matches/repositories/feed.repository';

/** A Prisma client that is either the base service or a transaction client, so
 *  a room's get-or-create can share the caller's `$transaction`. */
export type PrismaClientLike = PrismaService | Prisma.TransactionClient;

/** A room plus its single latest message (Prisma nested `take: 1`), the shape
 *  the conversation list is built from — no per-room N+1. */
export type RoomWithLastMessage = ChatRoom & { messages: ChatMessage[] };

@Injectable()
export class ConversationRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** Canonical (sorted) participant order so a pair maps to exactly one row
   *  regardless of who initiates — the `@@unique([user1Id, user2Id])` then
   *  guarantees no A/B vs B/A duplicate. */
  static canonicalPair(a: string, b: string): [string, string] {
    return a < b ? [a, b] : [b, a];
  }

  /** True when an ACCEPTED interest exists between the pair in EITHER direction
   *  — the sole gate for chat eligibility (checked on get-or-create AND on every
   *  send, never trusting that a room's prior existence still implies it). */
  async hasAcceptedInterest(a: string, b: string): Promise<boolean> {
    const count = await this.prisma.expressInterest.count({
      where: {
        status: 'ACCEPTED',
        OR: [
          { senderId: a, receiverId: b },
          { senderId: b, receiverId: a },
        ],
      },
    });
    return count > 0;
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

  findById(id: string): Promise<ChatRoom | null> {
    return this.prisma.chatRoom.findUnique({ where: { id } });
  }

  findByPair(a: string, b: string): Promise<ChatRoom | null> {
    const [user1Id, user2Id] = ConversationRepository.canonicalPair(a, b);
    return this.prisma.chatRoom.findUnique({
      where: { user1Id_user2Id: { user1Id, user2Id } },
    });
  }

  /** Idempotent get-or-create on the canonical pair. `create`-with-catch would
   *  also work; upsert keeps it to one statement and is race-safe against the
   *  unique constraint. */
  getOrCreate(
    client: PrismaClientLike,
    a: string,
    b: string,
  ): Promise<ChatRoom> {
    const [user1Id, user2Id] = ConversationRepository.canonicalPair(a, b);
    return client.chatRoom.upsert({
      where: { user1Id_user2Id: { user1Id, user2Id } },
      create: { user1Id, user2Id },
      update: {},
    });
  }

  /** One page of the caller's active rooms, newest-activity first, each with its
   *  latest message inlined. Rooms with no activity yet (no `lastMessageAt`)
   *  sort last. */
  listForUser(
    userId: string,
    skip: number,
    take: number,
  ): Promise<[RoomWithLastMessage[], number]> {
    const where: Prisma.ChatRoomWhereInput = {
      isActive: true,
      OR: [{ user1Id: userId }, { user2Id: userId }],
    };
    // Concurrent, not `$transaction([...])`: at READ COMMITTED (this database's
    // default) a transaction gives page/count no shared snapshot anyway, and it
    // costs a sequential BEGIN/COMMIT round trip either side — measured at
    // 307ms vs 74ms for the same two queries.
    return Promise.all([
      this.prisma.chatRoom.findMany({
        where,
        orderBy: [{ lastMessageAt: { sort: 'desc', nulls: 'last' } }],
        skip,
        take,
        include: {
          messages: {
            where: { deletedAt: null },
            orderBy: { createdAt: 'desc' },
            take: 1,
          },
        },
      }),
      this.prisma.chatRoom.count({ where }),
    ]);
  }

  /** Unread counts for a set of rooms in ONE grouped query (messages sent by the
   *  OTHER participant that the caller hasn't read). Returns a roomId→count map. */
  async unreadCountsByRoom(
    userId: string,
    roomIds: string[],
  ): Promise<Map<string, number>> {
    if (roomIds.length === 0) return new Map();
    const groups = await this.prisma.chatMessage.groupBy({
      by: ['roomId'],
      where: {
        roomId: { in: roomIds },
        senderId: { not: userId },
        isRead: false,
        deletedAt: null,
      },
      _count: { _all: true },
    });
    return new Map(groups.map((g) => [g.roomId, g._count._all]));
  }

  /** Blocks (either direction) between the caller and a set of peers, as a set
   *  of the peer ids that are blocked — one query for the whole page. */
  async blockedPeerIds(
    userId: string,
    peerIds: string[],
  ): Promise<Set<string>> {
    if (peerIds.length === 0) return new Set();
    const blocks = await this.prisma.userBlock.findMany({
      where: {
        OR: [
          { blockerId: userId, blockedUserId: { in: peerIds } },
          { blockedUserId: userId, blockerId: { in: peerIds } },
        ],
      },
      select: { blockerId: true, blockedUserId: true },
    });
    const set = new Set<string>();
    for (const b of blocks) {
      set.add(b.blockerId === userId ? b.blockedUserId : b.blockerId);
    }
    return set;
  }

  /** Public profile cards for a set of users, in the exact shape
   *  ProfileFeedMapper consumes (reuses the feed column selection). */
  findFeedProfilesByUserIds(userIds: string[]): Promise<FeedProfileRow[]> {
    if (userIds.length === 0) return Promise.resolve([]);
    return this.prisma.userProfile.findMany({
      where: { userId: { in: userIds } },
      select: FEED_PROFILE_SELECT,
    });
  }

  block(blockerId: string, blockedUserId: string): Promise<{ id: string }> {
    return this.prisma.userBlock.upsert({
      where: { blockerId_blockedUserId: { blockerId, blockedUserId } },
      create: { blockerId, blockedUserId },
      update: {},
      select: { id: true },
    });
  }

  async unblock(blockerId: string, blockedUserId: string): Promise<void> {
    await this.prisma.userBlock.deleteMany({
      where: { blockerId, blockedUserId },
    });
  }

  // ── per-user room state ────────────────────────────────────────────────────

  /** The caller's ChatParticipantState for a set of rooms, in one query — keyed
   *  by roomId. Rooms with no row yet just aren't present (all-defaults). */
  async statesByRoom(
    userId: string,
    roomIds: string[],
  ): Promise<Map<string, ChatParticipantState>> {
    if (roomIds.length === 0) return new Map();
    const states = await this.prisma.chatParticipantState.findMany({
      where: { userId, roomId: { in: roomIds } },
    });
    return new Map(states.map((s) => [s.roomId, s]));
  }

  /** Upserts the caller's state for a room (creates the row on first use). */
  upsertState(
    userId: string,
    roomId: string,
    patch: ChatStatePatch,
  ): Promise<ChatParticipantState> {
    return this.prisma.chatParticipantState.upsert({
      where: { roomId_userId: { roomId, userId } },
      create: { roomId, userId, ...patch },
      update: patch,
    });
  }
}
