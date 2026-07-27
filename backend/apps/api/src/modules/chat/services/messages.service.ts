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
  ChatMessage,
  ChatRoom,
  MessageType,
} from '../../../../../../libs/database/generated/client';
import { RealtimeGateway } from '../../realtime/realtime.gateway';
import { RealtimeEvents } from '../../realtime/realtime.events';
import { ConversationRepository } from '../repositories/conversation.repository';
import { MessageRepository } from '../repositories/message.repository';
import { SendMessageDto } from '../dto/send-message.dto';
import {
  MessageDto,
  MessagePageDto,
  deliveryStatusToWire,
} from '../dto/message.response.dto';

const MAX_TEXT_LENGTH = 4000;

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
      const items = await Promise.all(rows.map((m) => this.toDto(m, userId)));
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
    const items = await Promise.all(rows.map((m) => this.toDto(m, userId)));
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

    // Idempotency: a retried send with the same client key returns the message
    // the first request created — never a duplicate insert.
    if (dto.clientMessageId) {
      const existing = await this.messageRepository.findByClientKey(
        userId,
        dto.clientMessageId,
      );
      if (existing) return this.toDto(existing, userId, dto.clientMessageId);
    }

    // Delivery state: if the recipient has a live socket, the message goes out
    // DELIVERED; otherwise SENT, and the reconnect-replay path (chat.sync)
    // promotes it to DELIVERED when they come back online.
    const deliveredNow = this.realtime.isOnline(peerId);
    const now = new Date();

    let message: ChatMessage;
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
        });
        await this.messageRepository.touchRoomActivity(
          tx,
          dto.roomId,
          created.createdAt,
        );
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

    return senderView;
  }

  // ── internals ──────────────────────────────────────────────────────────

  private async requireParticipantRoom(
    roomId: string,
    userId: string,
  ): Promise<ChatRoom> {
    const room = await this.conversationRepository.findById(roomId);
    if (!room) throw new NotFoundException('Conversation not found.');
    if (room.user1Id !== userId && room.user2Id !== userId) {
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
      throw new ForbiddenException(
        'Users cannot message until interest is accepted.',
      );
    }
    if (blocked) {
      throw new ForbiddenException('You cannot message this member.');
    }
  }

  private peerOf(room: ChatRoom, userId: string): string {
    return room.user1Id === userId ? room.user2Id : room.user1Id;
  }

  async toDto(
    message: ChatMessage,
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
      ...(echoedClientId ? { clientMessageId: echoedClientId } : {}),
    };
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
