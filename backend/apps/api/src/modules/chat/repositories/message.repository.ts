import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  MessageDeliveryStatus,
  MessageType,
  Prisma,
} from '../../../../../../libs/database/generated/client';
import type { PrismaClientLike } from './conversation.repository';

export interface CreateMessageData {
  roomId: string;
  senderId: string;
  content: string;
  type: MessageType;
  mediaUrl?: string | null;
  clientMessageId?: string | null;
  status: MessageDeliveryStatus;
  deliveredAt?: Date | null;
  replyToMessageId?: string | null;
}

/** A [ChatMessage] with its (possibly null) reply-to message joined in — every
 *  method that feeds `MessagesService.toDto` returns this shape so the reply
 *  quote can be built without a second query. */
export type ChatMessageWithReply = Prisma.ChatMessageGetPayload<{
  include: { replyTo: true };
}>;

const WITH_REPLY = { include: { replyTo: true } } as const;

@Injectable()
export class MessageRepository {
  constructor(private readonly prisma: PrismaService) {}

  create(
    client: PrismaClientLike,
    data: CreateMessageData,
  ): Promise<ChatMessageWithReply> {
    return client.chatMessage.create({
      data: {
        roomId: data.roomId,
        senderId: data.senderId,
        content: data.content,
        type: data.type,
        mediaUrl: data.mediaUrl ?? null,
        clientMessageId: data.clientMessageId ?? null,
        status: data.status,
        deliveredAt: data.deliveredAt ?? null,
        replyToMessageId: data.replyToMessageId ?? null,
      },
      ...WITH_REPLY,
    });
  }

  findById(id: string): Promise<ChatMessageWithReply | null> {
    return this.prisma.chatMessage.findUnique({
      where: { id },
      ...WITH_REPLY,
    });
  }

  /** Replaces a message's text and stamps `editedAt`. */
  updateContent(
    id: string,
    content: string,
    editedAt: Date,
  ): Promise<ChatMessageWithReply> {
    return this.prisma.chatMessage.update({
      where: { id },
      data: { content, editedAt },
      ...WITH_REPLY,
    });
  }

  /** Soft-deletes a message (sets `deletedAt`); the row is kept for audit but
   *  excluded from every list/unread/replay query, all of which filter
   *  `deletedAt: null`. */
  softDelete(id: string, deletedAt: Date): Promise<ChatMessageWithReply> {
    return this.prisma.chatMessage.update({
      where: { id },
      data: { deletedAt },
      ...WITH_REPLY,
    });
  }

  /** Idempotency lookup — the existing message for this sender's client key, if
   *  a retried send already created it. */
  findByClientKey(
    senderId: string,
    clientMessageId: string,
  ): Promise<ChatMessageWithReply | null> {
    return this.prisma.chatMessage.findUnique({
      where: { senderId_clientMessageId: { senderId, clientMessageId } },
      ...WITH_REPLY,
    });
  }

  touchRoomActivity(
    client: PrismaClientLike,
    roomId: string,
    at: Date,
  ): Promise<unknown> {
    return client.chatRoom.update({
      where: { id: roomId },
      data: { lastMessageAt: at },
    });
  }

  listPaged(
    roomId: string,
    skip: number,
    take: number,
  ): Promise<[ChatMessageWithReply[], number]> {
    const where: Prisma.ChatMessageWhereInput = { roomId, deletedAt: null };
    return this.prisma.$transaction([
      this.prisma.chatMessage.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take,
        ...WITH_REPLY,
      }),
      this.prisma.chatMessage.count({ where }),
    ]);
  }

  /**
   * Keyset (cursor) page of a room's messages, newest-first. `cursorId` is the
   * id of the last (oldest) message the caller already holds; the page returned
   * is strictly older than it — unlike offset paging this doesn't shift or
   * duplicate rows when new messages arrive mid-scroll. A null cursor returns the
   * newest page. `take + 1` is fetched so `hasMore`/`nextCursor` come for free
   * (no separate COUNT). The secondary `id` ordering breaks same-millisecond
   * `createdAt` ties so the keyset is total and stable.
   */
  async listByCursor(
    roomId: string,
    cursorId: string | null,
    take: number,
  ): Promise<{
    items: ChatMessageWithReply[];
    hasMore: boolean;
    nextCursor: string | null;
  }> {
    const rows = await this.prisma.chatMessage.findMany({
      where: { roomId, deletedAt: null },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: take + 1,
      ...(cursorId ? { cursor: { id: cursorId }, skip: 1 } : {}),
      ...WITH_REPLY,
    });
    const hasMore = rows.length > take;
    const items = hasMore ? rows.slice(0, take) : rows;
    const nextCursor = hasMore ? items[items.length - 1].id : null;
    return { items, hasMore, nextCursor };
  }

  /** Marks every message the OTHER participant sent in this room READ (also
   *  covers the delivered step). Returns how many flipped. */
  async markRoomRead(roomId: string, readerId: string): Promise<number> {
    const now = new Date();
    const result = await this.prisma.chatMessage.updateMany({
      where: { roomId, senderId: { not: readerId }, status: { not: 'READ' } },
      data: { status: 'READ', isRead: true, readAt: now, deliveredAt: now },
    });
    return result.count;
  }

  /** Messages addressed to [userId] that were never delivered to them (sent
   *  while they were offline) — the reconnect-replay set. */
  findUndeliveredForUser(userId: string): Promise<ChatMessageWithReply[]> {
    return this.prisma.chatMessage.findMany({
      where: {
        status: 'SENT',
        senderId: { not: userId },
        deletedAt: null,
        room: { is: { OR: [{ user1Id: userId }, { user2Id: userId }] } },
      },
      orderBy: { createdAt: 'asc' },
      take: 200,
      ...WITH_REPLY,
    });
  }

  /**
   * Flips SENT→DELIVERED for a set of messages, one at a time — each a
   * single atomic conditional UPDATE (`WHERE id = ? AND status = 'SENT'`) —
   * and returns only the ids THIS call actually changed (a subset of
   * `ids`). A racing concurrent call for the same message (e.g. this same
   * recipient's other device replaying `chat.sync` at the same moment, or
   * an explicit delivery ack landing right after a replay already handled
   * it) will find `status` no longer `SENT` and match zero rows for it, so
   * it's correctly excluded from that call's own return value too — this
   * is what lets callers notify/re-push only for genuinely new
   * transitions instead of every caller unconditionally broadcasting for
   * the full requested set, which is what produced duplicate
   * `chat.delivered` events under concurrent replay.
   */
  async markDelivered(ids: string[]): Promise<string[]> {
    if (ids.length === 0) return [];
    const now = new Date();
    const changed: string[] = [];
    for (const id of ids) {
      const result = await this.prisma.chatMessage.updateMany({
        where: { id, status: 'SENT' },
        data: { status: 'DELIVERED', deliveredAt: now },
      });
      if (result.count > 0) changed.push(id);
    }
    return changed;
  }
}
