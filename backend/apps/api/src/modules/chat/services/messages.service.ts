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
import { ActiveConversationService } from '../../realtime/active-conversation.service';
import { RealtimeEvents } from '../../realtime/realtime.events';
import { NotificationsService } from '../../notifications/services/notifications.service';
import type { CreateNotificationData } from '../../notifications/repositories/notification.repository';
import { ConversationRepository } from '../repositories/conversation.repository';
import {
  MessageRepository,
  ChatMessageWithReply,
} from '../repositories/message.repository';
import { ChatAuditService, ChatAuditAction } from './chat-audit.service';
import { EmailDispatchService } from '../../notifications/services/email-dispatch.service';
import { SendMessageDto } from '../dto/send-message.dto';
import {
  MediaUrlRefreshDto,
  MessageDto,
  MessagePageDto,
  MessageReplyDto,
  deliveryStatusToWire,
} from '../dto/message.response.dto';

const MAX_TEXT_LENGTH = 4000;
// A chat push shows the message itself; anything past this is cut — the
// recipient reads the rest by opening the conversation. The ellipsis is
// included in the budget, so a truncated body is never longer than this.
const PUSH_BODY_MAX_LENGTH = 120;
// Shown as the push title when the sender has no finalized profile to take a
// display name from (see NotificationRepository.findDisplayName for the
// resolution order). Deliberately NOT 'New message': that is the stored
// notification row's generic title, so reusing it here makes a fallback push
// indistinguishable from the pre-dynamic-title behavior — you cannot tell
// "the fix isn't running" from "this sender has no profile". The brand name
// is the last resort because the only other User-level identifiers in the
// schema are `email` and `phone`, which must never reach a lock screen.
const FALLBACK_PUSH_TITLE = 'Nenjam';
// A media message's stored content is a signed, short-lived S3 URL — never
// previewable — so the push describes it instead.
const MEDIA_PUSH_PREVIEW = 'Sent you an attachment.';
// A sender may edit their own text message only within this window after
// sending it (matching the client's affordance); after that it's immutable.
const EDIT_WINDOW_MS = 15 * 60 * 1000;

function isUniqueViolation(error: unknown): boolean {
  return (error as { code?: string })?.code === 'P2002';
}

/** Message text as it appears in a push body: newlines/runs of whitespace
 *  collapsed (a notification renders on one or two lines) and cut to
 *  {@link PUSH_BODY_MAX_LENGTH}, ellipsis included in that budget. */
function truncateForPush(text: string): string {
  const collapsed = text.replace(/\s+/g, ' ').trim();
  if (collapsed.length <= PUSH_BODY_MAX_LENGTH) return collapsed;
  return `${collapsed.slice(0, PUSH_BODY_MAX_LENGTH - 1).trimEnd()}…`;
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
    private readonly emailDispatch: EmailDispatchService,
    private readonly activeConversation: ActiveConversationService,
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
    // The two identities every downstream side effect (notification, push,
    // email, realtime) is routed by. Both are derived from the room row, never
    // from the request body: the sender is the authenticated caller, the
    // receiver is the room's other participant.
    const senderUserId = userId;
    const room = await this.requireParticipantRoom(dto.roomId, senderUserId);
    if (!room.isActive) {
      throw new ForbiddenException('This conversation is no longer available.');
    }
    const receiverUserId = this.peerOf(room, senderUserId);

    await this.assertChatEligible(senderUserId, receiverUserId);

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
        senderUserId,
        dto.clientMessageId,
      );
      if (existing)
        return this.toDto(existing, senderUserId, dto.clientMessageId);
    }

    // Delivery state: if the recipient has a live socket (per cross-instance
    // presence), the message goes out DELIVERED; otherwise SENT, and the
    // reconnect-replay path (chat.sync) promotes it to DELIVERED when they come
    // back online.
    //
    // The sender's display name is resolved here, before the transaction,
    // because the notification row written inside it now carries that name as
    // its title — it can no longer be looked up lazily after commit. Issued
    // alongside the presence read (both are independent single-row lookups) so
    // it adds no extra round trip to the send path.
    // `recipientIsViewing` joins this batch rather than being read later: it now
    // decides whether the notification row is written INSIDE the transaction
    // below, so it has to be known before the transaction opens. Riding along in
    // the existing Promise.all keeps the send path at the same number of round
    // trips, which matters — a round trip to this database measures ~342ms.
    //
    // `.catch(() => false)` is load-bearing here exactly as at the push call
    // site: a lookup we cannot answer must fall back to NOTIFYING, never to
    // silence.
    const [deliveredNow, senderDisplayName, recipientIsViewing] =
      await Promise.all([
        this.presence.isOnline(receiverUserId),
        this.resolveSenderTitle(senderUserId),
        this.activeConversation
          .isViewing(receiverUserId, dto.roomId)
          .catch(() => false),
      ]);
    const now = new Date();

    // One title/body pair, used verbatim for both the stored notification row
    // and the push payload — the notification center and the lock screen must
    // never disagree about what a message said.
    const notificationBody = truncateForPush(
      isMedia ? MEDIA_PUSH_PREVIEW : content,
    );

    let message: ChatMessageWithReply;
    let notificationData: CreateNotificationData | undefined;
    try {
      message = await this.prisma.$transaction(async (tx) => {
        const created = await this.messageRepository.create(tx, {
          roomId: dto.roomId,
          senderId: senderUserId,
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
        //
        // Skipped entirely when the recipient has THIS conversation open. They
        // are watching the message land over the socket, so a Notification-tab
        // entry for it is an item they must then dismiss for something they
        // already read — and it would inflate the unread badge for a thread
        // they are actively in.
        //
        // Being online is deliberately NOT the condition: someone in a
        // different conversation, or anywhere else in the app, still gets the
        // row. See ActiveConversationService.
        //
        // Also removes one write from the transaction on this path, which is
        // worth having when a round trip costs ~342ms.
        if (!recipientIsViewing) {
          notificationData = {
            userId: receiverUserId,
            type: 'NEW_MESSAGE',
            title: senderDisplayName,
            body: notificationBody,
            data: { actorId: senderUserId, referenceId: dto.roomId },
          };
          await this.notifications.create(tx, notificationData);
        }

        return created;
      });
    } catch (error) {
      // Concurrent retry with the same client key lost the unique race — return
      // the message the winner created.
      if (isUniqueViolation(error) && dto.clientMessageId) {
        const existing = await this.messageRepository.findByClientKey(
          senderUserId,
          dto.clientMessageId,
        );
        if (existing)
          return this.toDto(existing, senderUserId, dto.clientMessageId);
      }
      throw error;
    }

    // Real-time (after commit): push the full message inline to the recipient
    // (renders instantly, no round trip) and to the sender's OTHER devices.
    const senderView = await this.toDto(
      message,
      senderUserId,
      dto.clientMessageId,
    );
    const recipientView = await this.toDto(message, receiverUserId);
    this.realtime.emitToUser(receiverUserId, RealtimeEvents.chatMessage, {
      ...recipientView,
    });
    this.realtime.emitToUser(senderUserId, RealtimeEvents.chatMessage, {
      ...senderView,
    });

    // Notification center + push (after commit) — same rule and fire-and-forget
    // dispatch as Interests/Shortlist: a rolled-back transaction must never
    // reach a device as a push, and a push failure must never fail this call.
    //
    // Both are skipped when no notification row was written (recipient has this
    // conversation open). Guarding on `notificationData` rather than re-reading
    // `recipientIsViewing` keeps the two decisions from ever drifting apart:
    // there is exactly one condition under which the row is absent, and this is
    // it. It also drops a Redis round trip and a push on that path.
    if (notificationData) {
      await this.notifications.invalidateUnread(receiverUserId);
      void this.dispatchNewMessagePush({
        notification: notificationData,
        senderUserId,
        receiverUserId,
        conversationId: message.roomId,
        title: senderDisplayName,
        body: notificationBody,
      });
      // Only signal "a notification appeared" when one actually did — otherwise
      // the recipient's notification list refreshes for a row that does not
      // exist.
      this.realtime.emitToUser(
        receiverUserId,
        RealtimeEvents.notificationCreated,
        {
          id: message.id,
          at: recipientView.createdAt,
        },
      );
    }

    void this.audit.record({
      actorId: senderUserId,
      action: ChatAuditAction.messageSend,
      entity: 'ChatMessage',
      entityId: message.id,
      metadata: { roomId: message.roomId, type: message.type },
    });

    // Email the recipient only when they were NOT connected when this was
    // sent — `deliveredNow` is the same presence read the delivery-status
    // write above already made, so this costs no extra query. Someone with
    // the app open gets the real-time event and would only be annoyed by mail.
    //
    // Media messages send no preview: their content is a signed S3 URL that
    // expires long before the email is read.
    if (!deliveredNow) {
      void this.emailDispatch
        .sendNewMessage(
          receiverUserId,
          senderUserId,
          isMedia ? MEDIA_PUSH_PREVIEW : content,
          message.roomId,
        )
        .catch(() => undefined);
    }

    return senderView;
  }

  /**
   * The sender's display name, used as the title of both the stored
   * notification row and the push. Falls back to {@link FALLBACK_PUSH_TITLE}
   * when they have no finalized profile.
   *
   * Swallows every failure: unlike the old post-commit lookup, this now runs
   * before the send transaction, so a thrown error here would fail the message
   * send itself. A name we could not read is worth a generic title, never a
   * refused message.
   */
  private async resolveSenderTitle(senderUserId: string): Promise<string> {
    try {
      const name = await this.notifications.resolveDisplayName(senderUserId);
      return name ?? FALLBACK_PUSH_TITLE;
    } catch {
      return FALLBACK_PUSH_TITLE;
    }
  }

  /**
   * Push for a new chat message.
   *
   * Recipient logic is explicit on both sides: the push is addressed to
   * `receiverUserId` only, and `excludeUserId: senderUserId` drops every
   * device token registered to the sender before the send. Addressing alone
   * is not enough — a single physical device that has been registered to both
   * accounts (shared phone, account switch, a logout whose token cleanup
   * never landed) still sits in the recipient's token list, which is how a
   * sender ends up notified of their own message. The exclusion closes that.
   *
   * `title`/`body` arrive already resolved and truncated from {@link send},
   * which needs the same pair for the notification row it writes inside the
   * transaction — one lookup feeds both channels, so the notification center
   * and the lock screen can never disagree. Fire-and-forget by the caller;
   * never throws (a push failure must not surface on a message send that
   * already succeeded).
   */
  private async dispatchNewMessagePush(params: {
    notification: CreateNotificationData;
    senderUserId: string;
    receiverUserId: string;
    conversationId: string;
    title: string;
    body: string;
  }): Promise<void> {
    const { senderUserId, receiverUserId, conversationId, title, body } =
      params;
    try {
      // Deliberately a SECOND check, not a duplicate of the pre-transaction
      // one. That decided whether to write the notification row; this decides
      // whether to buzz a device, and the two are separated by the whole
      // transaction — which on this deployment is hundreds of milliseconds
      // (~342ms per round trip). A recipient who opened the thread inside that
      // window should not get a push, and only re-reading catches it. One extra
      // Redis read (~40ms) to avoid buzzing someone mid-read is a good trade.
      //
      // Suppress the push when the recipient already has THIS conversation on
      // screen — they are watching the message arrive over the socket, so a
      // lock-screen buzz for it is pure noise.
      //
      // Scoped to the exact thread on purpose. Being online, or merely having
      // the app open, is far too broad: someone on Discover or in a different
      // conversation still needs telling. See ActiveConversationService.
      //
      // Only the PUSH is skipped. The notification row was already written
      // inside the send transaction and is untouched, so the notification
      // centre and unread count stay correct either way.
      // `.catch(() => false)` is load-bearing, not defensive noise. The
      // surrounding try/catch swallows everything to keep push best-effort, so
      // without this a lookup error would fall straight past dispatchPush and
      // silently drop a real notification — failing CLOSED, the one direction
      // this feature must never fail in. A lookup we cannot answer means send.
      const recipientIsViewing = await this.activeConversation
        .isViewing(receiverUserId, conversationId)
        .catch(() => false);
      if (recipientIsViewing) return;
      await this.notifications.dispatchPush(
        { ...params.notification, userId: receiverUserId },
        {
          excludeUserId: senderUserId,
          override: {
            title,
            body,
            data: {
              type: 'chat',
              conversationId,
              senderId: senderUserId,
            },
          },
        },
      );
    } catch {
      // Best-effort, same contract as PushDispatchService.dispatchToUser.
    }
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
