import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '@app/database';
import { S3Service } from '@app/storage';
import { MessageListQueryDto } from '../dto/message-list-query.dto';
import type {
  ChatRoom,
  MessageType,
} from '../../../../../../libs/database/generated/client';
import { RealtimeGateway } from '../../realtime/realtime.gateway';
import { PresenceService } from '../../realtime/presence.service';
import { RealtimeEvents } from '../../realtime/realtime.events';
import { NotificationsService } from '../../notifications/services/notifications.service';
import type { CreateNotificationData } from '../../notifications/repositories/notification.repository';
import { ConversationRepository } from '../repositories/conversation.repository';
import {
  MessageRepository,
  ChatMessageWithReply,
} from '../repositories/message.repository';
import { ChatAuditService, ChatAuditAction } from './chat-audit.service';
import { SendMessageDto } from '../dto/send-message.dto';
import {
  MediaUrlRefreshDto,
  MessageDto,
  MessagePageDto,
  MessageReplyDto,
  deliveryStatusToWire,
} from '../dto/message.response.dto';

const MAX_TEXT_LENGTH = 4000;
// A sender may edit their own text message only within this window after
// sending it (matching the client's affordance); after that it's immutable.
const EDIT_WINDOW_MS = 15 * 60 * 1000;

function isUniqueViolation(error: unknown): boolean {
  return (error as { code?: string })?.code === 'P2002';
}

/**
 * Message read/send. Every path re-derives authorization from the DB, never the
 * request: the caller must be a participant in the room AND (at send time) still
 * chat-eligible (an ACCEPTED interest exists and neither party has blocked the
 * other) — a room existing once is not proof it's still eligible. Media URLs are
 * presigned per read (short-lived), never stored/returned as permanent links.
 */
@Injectable()
export class MessagesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly conversationRepository: ConversationRepository,
    private readonly messageRepository: MessageRepository,
    private readonly s3: S3Service,
    private readonly realtime: RealtimeGateway,
    private readonly presence: PresenceService,
    private readonly audit: ChatAuditService,
    private readonly notifications: NotificationsService,
  ) {}

  async list(
    userId: string,
    query: MessageListQueryDto,
  ): Promise<MessagePageDto> {
    const conversationId = query.conversationId;
    await this.requireParticipantRoom(conversationId, userId);

    const { take, pageNumber } = query;

    // Keyset mode — opt-in by sending `cursor` (even empty, for the first page).
    // Stable under concurrent inserts, so it's the preferred path for scrollback.
    if (query.cursor !== undefined) {
      const {
        items: rows,
        hasMore,
        nextCursor,
      } = await this.messageRepository.listByCursor(
        conversationId,
        query.cursor || null,
        take,
      );
      // Repository rows come back newest-first (the DB order needed to grab
      // "the last N"/"the N before this cursor"); the wire contract for a page
      // is oldest-first, matching how the client renders/prepends it.
      const items = await Promise.all(
        rows.map((m) => this.toDto(m, userId)),
      ).then((dtos) => dtos.reverse());
      return {
        items,
        page: pageNumber,
        limit: take,
        total: items.length,
        hasMore,
        nextCursor,
      };
    }

    // Legacy offset mode (`?page=&limit=`) — unchanged, still the default.
    const { skip } = query;
    const [rows, total] = await this.messageRepository.listPaged(
      conversationId,
      skip,
      take,
    );
    // Same newest-first -> oldest-first reversal as the keyset branch above.
    const items = await Promise.all(
      rows.map((m) => this.toDto(m, userId)),
    ).then((dtos) => dtos.reverse());
    return {
      items,
      page: pageNumber,
      limit: take,
      total,
      hasMore: skip + rows.length < total,
      nextCursor: null,
    };
  }

  async send(userId: string, dto: SendMessageDto): Promise<MessageDto> {
    const room = await this.requireParticipantRoom(dto.roomId, userId);
    if (!room.isActive) {
      throw new ForbiddenException('This conversation is no longer available.');
    }
    const peerId = this.peerOf(room, userId);

    await this.assertChatEligible(userId, peerId);

    const type: MessageType = dto.type ?? 'TEXT';
    const content = (dto.content ?? '').trim();
    const isMedia = type !== 'TEXT';
    if (isMedia && !dto.mediaUrl) {
      throw new BadRequestException('A media message requires a mediaUrl.');
    }
    if (!isMedia && content.length === 0) {
      throw new BadRequestException('Message text cannot be empty.');
    }
    if (content.length > MAX_TEXT_LENGTH) {
      throw new BadRequestException('Message is too long.');
    }

    // A reply target must exist and belong to this same room — cross-room
    // (or nonexistent) ids are rejected outright. Replying to an already
    // edited or soft-deleted message is explicitly allowed; the reply just
    // carries whatever that message's current state is.
    if (dto.replyToMessageId) {
      const replyTarget = await this.messageRepository.findById(
        dto.replyToMessageId,
      );
      if (!replyTarget || replyTarget.roomId !== dto.roomId) {
        throw new BadRequestException(
          'The message being replied to could not be found in this conversation.',
        );
      }
    }

    // Idempotency: a retried send with the same client key returns the message
    // the first request created — never a duplicate insert.
    if (dto.clientMessageId) {
      const existing = await this.messageRepository.findByClientKey(
        userId,
        dto.clientMessageId,
      );
      if (existing) return this.toDto(existing, userId, dto.clientMessageId);
    }

    // Delivery state: if the recipient has a live socket (per cross-instance
    // presence), the message goes out DELIVERED; otherwise SENT, and the
    // reconnect-replay path (chat.sync) promotes it to DELIVERED when they come
    // back online.
    const deliveredNow = await this.presence.isOnline(peerId);
    const now = new Date();

    let message: ChatMessageWithReply;
    let notificationData: CreateNotificationData | undefined;
    try {
      message = await this.prisma.$transaction(async (tx) => {
        const created = await this.messageRepository.create(tx, {
          roomId: dto.roomId,
          senderId: userId,
          content,
          type,
          mediaUrl: dto.mediaUrl ?? null,
          clientMessageId: dto.clientMessageId ?? null,
          status: deliveredNow ? 'DELIVERED' : 'SENT',
          deliveredAt: deliveredNow ? now : null,
          replyToMessageId: dto.replyToMessageId ?? null,
        });
        await this.messageRepository.touchRoomActivity(
          tx,
          dto.roomId,
          created.createdAt,
        );

        // Notify the recipient only — never the sender. Same
        // create-inside-transaction pattern as Interests/Shortlist.
        notificationData = {
          userId: peerId,
          type: 'NEW_MESSAGE',
          title: 'New message',
          body: 'You have a new message.',
          data: { actorId: userId, referenceId: dto.roomId },
        };
        await this.notifications.create(tx, notificationData);

        return created;
      });
    } catch (error) {
      // Concurrent retry with the same client key lost the unique race — return
      // the message the winner created.
      if (isUniqueViolation(error) && dto.clientMessageId) {
        const existing = await this.messageRepository.findByClientKey(
          userId,
          dto.clientMessageId,
        );
        if (existing) return this.toDto(existing, userId, dto.clientMessageId);
      }
      throw error;
    }

    // Real-time (after commit): push the full message inline to the recipient
    // (renders instantly, no round trip) and to the sender's OTHER devices.
    const senderView = await this.toDto(message, userId, dto.clientMessageId);
    const recipientView = await this.toDto(message, peerId);
    this.realtime.emitToUser(peerId, RealtimeEvents.chatMessage, {
      ...recipientView,
    });
    this.realtime.emitToUser(userId, RealtimeEvents.chatMessage, {
      ...senderView,
    });

    // Notification center + push (after commit) — same rule and fire-and-forget
    // dispatch as Interests/Shortlist: a rolled-back transaction must never
    // reach a device as a push, and a push failure must never fail this call.
    await this.notifications.invalidateUnread(peerId);
    void this.notifications.dispatchPush(notificationData!);
    this.realtime.emitToUser(peerId, RealtimeEvents.notificationCreated, {
      id: message.id,
      at: recipientView.createdAt,
    });

    void this.audit.record({
      actorId: userId,
      action: ChatAuditAction.messageSend,
      entity: 'ChatMessage',
      entityId: message.id,
      metadata: { roomId: message.roomId, type: message.type },
    });

    return senderView;
  }

  /**
   * Edit a message's text. Sender-only, text-only, and only within
   * {@link EDIT_WINDOW_MS} of sending; media and already-deleted messages can't
   * be edited. Stamps `editedAt` and broadcasts the updated message to both
   * participants so their bubble re-renders in place.
   */
  async edit(
    userId: string,
    messageId: string,
    rawContent: string,
  ): Promise<MessageDto> {
    const message = await this.messageRepository.findById(messageId);
    if (!message || message.deletedAt) {
      throw new NotFoundException('Message not found.');
    }
    if (message.senderId !== userId) {
      this.audit.recordDenied(userId, 'ChatMessage', messageId, 'not-sender', {
        op: 'edit',
      });
      throw new ForbiddenException('You can only edit your own messages.');
    }
    if (message.type !== 'TEXT') {
      throw new BadRequestException('Only text messages can be edited.');
    }
    if (Date.now() - message.createdAt.getTime() > EDIT_WINDOW_MS) {
      throw new ForbiddenException(
        'The edit window for this message has passed.',
      );
    }
    const content = (rawContent ?? '').trim();
    if (content.length === 0) {
      throw new BadRequestException('Message text cannot be empty.');
    }
    if (content.length > MAX_TEXT_LENGTH) {
      throw new BadRequestException('Message is too long.');
    }

    const now = new Date();
    const updated = await this.messageRepository.updateContent(
      messageId,
      content,
      now,
    );

    const room = await this.conversationRepository.findById(updated.roomId);
    if (room) {
      const peerId = this.peerOf(room, userId);
      const peerView = await this.toDto(updated, peerId);
      const senderView = await this.toDto(updated, userId);
      this.realtime.emitToUser(peerId, RealtimeEvents.chatMessageEdited, {
        ...peerView,
      });
      this.realtime.emitToUser(userId, RealtimeEvents.chatMessageEdited, {
        ...senderView,
      });
    }

    void this.audit.record({
      actorId: userId,
      action: ChatAuditAction.messageEdit,
      entity: 'ChatMessage',
      entityId: messageId,
      metadata: { roomId: updated.roomId },
    });
    return this.toDto(updated, userId);
  }

  /**
   * Soft-delete a message (delete for everyone). Sender-only. The row is kept
   * (audit) but disappears from history — every read path filters `deletedAt`.
   * Broadcasts `chat.messageDeleted` so both participants drop the bubble live.
   */
  async remove(userId: string, messageId: string): Promise<void> {
    const message = await this.messageRepository.findById(messageId);
    if (!message || message.deletedAt) {
      throw new NotFoundException('Message not found.');
    }
    if (message.senderId !== userId) {
      this.audit.recordDenied(userId, 'ChatMessage', messageId, 'not-sender', {
        op: 'delete',
      });
      throw new ForbiddenException('You can only delete your own messages.');
    }

    const now = new Date();
    await this.messageRepository.softDelete(messageId, now);

    const room = await this.conversationRepository.findById(message.roomId);
    if (room) {
      const payload = {
        id: messageId,
        roomId: message.roomId,
        at: now.toISOString(),
      };
      this.realtime.emitToUser(
        this.peerOf(room, userId),
        RealtimeEvents.chatMessageDeleted,
        payload,
      );
      this.realtime.emitToUser(
        userId,
        RealtimeEvents.chatMessageDeleted,
        payload,
      );
    }

    void this.audit.record({
      actorId: userId,
      action: ChatAuditAction.messageDelete,
      entity: 'ChatMessage',
      entityId: messageId,
      metadata: { roomId: message.roomId },
    });
  }

  /**
   * Explicit client-driven delivery acknowledgment (see
   * `ChatGateway.handleDeliveredAck`'s doc comment for why this exists
   * alongside the presence heuristic in {@link send}). `userId` must be a
   * participant in the message's room and NOT its sender — re-derived from
   * the DB, never trusted from the socket payload. Silently no-ops for any
   * invalid/unauthorized/already-deleted case rather than throwing — this
   * is a best-effort background signal, not a request with a caller
   * waiting on a response.
   */
  async acknowledgeDelivered(userId: string, messageId: string): Promise<void> {
    const message = await this.messageRepository.findById(messageId);
    if (!message || message.deletedAt || message.senderId === userId) return;

    const room = await this.conversationRepository.findById(message.roomId);
    if (!room || (room.user1Id !== userId && room.user2Id !== userId)) return;

    const changed = await this.messageRepository.markDelivered([messageId]);
    if (changed.length === 0) return; // already DELIVERED/READ — nothing new to announce

    this.realtime.emitToUser(message.senderId, RealtimeEvents.chatDelivered, {
      id: message.id,
      roomId: message.roomId,
      at: new Date().toISOString(),
    });
  }

  // ── internals ──────────────────────────────────────────────────────────

  private async requireParticipantRoom(
    roomId: string,
    userId: string,
  ): Promise<ChatRoom> {
    const room = await this.conversationRepository.findById(roomId);
    if (!room) throw new NotFoundException('Conversation not found.');
    if (room.user1Id !== userId && room.user2Id !== userId) {
      this.audit.recordDenied(userId, 'ChatRoom', roomId, 'not-a-participant');
      throw new ForbiddenException(
        'You are not a participant in this conversation.',
      );
    }
    return room;
  }

  private async assertChatEligible(
    userId: string,
    peerId: string,
  ): Promise<void> {
    const [accepted, blocked] = await Promise.all([
      this.conversationRepository.hasAcceptedInterest(userId, peerId),
      this.conversationRepository.isBlockedBetween(userId, peerId),
    ]);
    if (!accepted) {
      this.audit.recordDenied(
        userId,
        'ChatRoom',
        null,
        'interest-not-accepted',
        {
          peerId,
        },
      );
      throw new ForbiddenException(
        'Users cannot message until interest is accepted.',
      );
    }
    if (blocked) {
      this.audit.recordDenied(userId, 'ChatRoom', null, 'blocked', { peerId });
      throw new ForbiddenException('You cannot message this member.');
    }
  }

  private peerOf(room: ChatRoom, userId: string): string {
    return room.user1Id === userId ? room.user2Id : room.user1Id;
  }

  async toDto(
    message: ChatMessageWithReply,
    viewerId: string,
    clientMessageId?: string,
  ): Promise<MessageDto> {
    const echoedClientId = clientMessageId ?? message.clientMessageId;
    return {
      id: message.id,
      roomId: message.roomId,
      senderId: message.senderId,
      isMine: message.senderId === viewerId,
      content: message.content,
      type: message.type,
      mediaUrl: await this.presignMedia(message.mediaUrl),
      isRead: message.isRead,
      status: deliveryStatusToWire(message.status),
      createdAt: message.createdAt.toISOString(),
      editedAt: message.editedAt ? message.editedAt.toISOString() : null,
      replyTo: await this.toReplyDto(message.replyTo, viewerId),
      ...(echoedClientId ? { clientMessageId: echoedClientId } : {}),
    };
  }

  /** Builds the slim reply-quote snapshot for [MessageDto.replyTo] — always
   *  read live off the joined `replyTo` relation (see
   *  `ChatMessageWithReply`'s doc comment), so an edit or delete to the
   *  original is reflected the next time this message's DTO is built. Media
   *  is skipped (not presigned) for an already-deleted original since the
   *  client never renders it — no point spending an S3 call on it. */
  private async toReplyDto(
    replyTo: ChatMessageWithReply['replyTo'],
    viewerId: string,
  ): Promise<MessageReplyDto | null> {
    if (!replyTo) return null;
    const isDeleted = replyTo.deletedAt != null;
    return {
      id: replyTo.id,
      isMine: replyTo.senderId === viewerId,
      type: replyTo.type,
      content: replyTo.content,
      mediaUrl: isDeleted ? null : await this.presignMedia(replyTo.mediaUrl),
      isDeleted,
      editedAt: replyTo.editedAt ? replyTo.editedAt.toISOString() : null,
    };
  }

  /**
   * Re-presigns [messageId]'s media URL — called when the client detects its
   * previously-issued presigned URL has expired (a 403 loading it). Requires
   * the caller to still be a participant in the message's room (same
   * re-derive-from-DB authorization as every other message operation); never
   * increases the URL's lifetime beyond the normal short-lived expiry
   * {@link presignMedia} already uses, and never returns a permanent public
   * link. Returns `{ mediaUrl: null }` (not a thrown error) for a text
   * message or if S3 presigning itself fails — this is a best-effort
   * refresh, not a critical path.
   */
  async refreshMediaUrl(
    userId: string,
    messageId: string,
  ): Promise<MediaUrlRefreshDto> {
    const message = await this.messageRepository.findById(messageId);
    if (!message) {
      throw new NotFoundException('Message not found.');
    }
    await this.requireParticipantRoom(message.roomId, userId);
    return { mediaUrl: await this.presignMedia(message.mediaUrl) };
  }

  /** Stored `mediaUrl` is an S3 object key; return a short-lived presigned URL.
   *  A value that's already an absolute URL (defensive) is passed through. */
  private async presignMedia(value: string | null): Promise<string | null> {
    if (!value) return null;
    if (/^https?:\/\//i.test(value)) return value;
    if (!this.s3.isConfigured()) return null;
    try {
      return await this.s3.getPresignedGetUrl(value);
    } catch {
      return null;
    }
  }
}
