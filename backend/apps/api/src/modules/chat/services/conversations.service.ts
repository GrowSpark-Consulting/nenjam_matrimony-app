import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '@app/database';
import { PaginationQueryDto } from '@app/common';
import type {
  ChatMessage,
  ChatRoom,
} from '../../../../../../libs/database/generated/client';
import { ProfileFeedMapper } from '../../matches/mappers/profile-feed.mapper';
import { RealtimeGateway } from '../../realtime/realtime.gateway';
import { RealtimeEvents } from '../../realtime/realtime.events';
import {
  ChatStatePatch,
  ConversationRepository,
} from '../repositories/conversation.repository';
import { MessageRepository } from '../repositories/message.repository';
import { ChatAuditService, ChatAuditAction } from './chat-audit.service';
import {
  ConversationDto,
  ConversationPageDto,
  GetOrCreateConversationResponseDto,
} from '../dto/conversation.response.dto';
import { deliveryStatusToWire } from '../dto/message.response.dto';

/**
 * Conversation lifecycle. Creating (or opening) a conversation is gated on an
 * ACCEPTED interest between the pair — enforced server-side, independent of any
 * frontend check. Every :id operation verifies the caller is one of the room's
 * two participants. The list is assembled with no N+1 (last message inlined,
 * unread counts + blocks + peer profiles each batched).
 */
@Injectable()
export class ConversationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly conversationRepository: ConversationRepository,
    private readonly messageRepository: MessageRepository,
    private readonly profileMapper: ProfileFeedMapper,
    private readonly realtime: RealtimeGateway,
    private readonly audit: ChatAuditService,
  ) {}

  async list(
    userId: string,
    pagination: PaginationQueryDto,
  ): Promise<ConversationPageDto> {
    const { skip, take, pageNumber } = pagination;
    const [rooms, total] = await this.conversationRepository.listForUser(
      userId,
      skip,
      take,
    );
    if (rooms.length === 0) {
      return {
        items: [],
        page: pageNumber,
        limit: take,
        total,
        hasMore: false,
      };
    }

    const roomIds = rooms.map((r) => r.id);
    const peerIds = rooms.map((room) => this.peerOf(room, userId));
    const [unreadByRoom, blockedPeers, profileRows, statesByRoom] =
      await Promise.all([
        this.conversationRepository.unreadCountsByRoom(userId, roomIds),
        this.conversationRepository.blockedPeerIds(userId, peerIds),
        this.conversationRepository.findFeedProfilesByUserIds([
          ...new Set(peerIds),
        ]),
        this.conversationRepository.statesByRoom(userId, roomIds),
      ]);
    const profileDtos = await this.profileMapper.toDtoList(profileRows);
    const profileByUserId = new Map(profileDtos.map((dto) => [dto.id, dto]));

    const items: ConversationDto[] = [];
    for (const room of rooms) {
      const peerId = this.peerOf(room, userId);
      const profile = profileByUserId.get(peerId);
      if (!profile) continue; // peer has no finalized profile — can't render
      const state = statesByRoom.get(room.id);
      const lastAt = room.lastMessageAt ?? room.createdAt;
      // Delete-for-me: the room stays hidden until a message NEWER than the
      // delete point arrives — then it reappears with only that fresh history.
      if (state?.deletedUntil && lastAt <= state.deletedUntil) continue;
      const last = room.messages[0] as ChatMessage | undefined;
      const fromMe = last?.senderId === userId;
      const realUnread = unreadByRoom.get(room.id) ?? 0;
      // "Mark as unread" is a UI affordance — surface at least one unread when
      // the user set it and nothing genuinely unread already covers it.
      const unreadCount =
        state?.markUnread && realUnread === 0 ? 1 : realUnread;
      items.push({
        id: room.id,
        profile,
        lastMessage: last ? this.lastMessageLabel(last) : '',
        lastMessageAt: lastAt.toISOString(),
        unreadCount,
        lastMessageFromMe: Boolean(fromMe),
        isBlocked: blockedPeers.has(peerId),
        lastMessageStatus:
          last && fromMe ? deliveryStatusToWire(last.status) : null,
        isPinned: state?.isPinned ?? false,
        isMuted: state?.isMuted ?? false,
        isArchived: state?.isArchived ?? false,
        isTyping: false,
        isLocked: false,
        smartIndicator: 'none',
      });
    }

    // Pinned conversations float to the top of the page; the sort is stable
    // (V8), so within each group the newest-activity order from the query holds.
    items.sort((a, b) => Number(b.isPinned) - Number(a.isPinned));

    return {
      items,
      page: pageNumber,
      limit: take,
      total,
      hasMore: skip + rooms.length < total,
    };
  }

  async getOrCreate(
    userId: string,
    peerId: string,
  ): Promise<GetOrCreateConversationResponseDto> {
    if (userId === peerId) {
      throw new BadRequestException(
        'You cannot start a conversation with yourself.',
      );
    }
    if (
      !(await this.conversationRepository.hasAcceptedInterest(userId, peerId))
    ) {
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

    const room = await this.prisma.$transaction((tx) =>
      this.conversationRepository.getOrCreate(tx, userId, peerId),
    );

    void this.audit.record({
      actorId: userId,
      action: ChatAuditAction.conversationCreate,
      entity: 'ChatRoom',
      entityId: room.id,
      metadata: { peerId },
    });

    const [lastRows] = await this.messageRepository.listPaged(room.id, 0, 1);
    const last = lastRows[0];
    return {
      id: room.id,
      lastMessage: last ? this.lastMessageLabel(last) : '',
      lastMessageAt: (room.lastMessageAt ?? room.createdAt).toISOString(),
    };
  }

  async markRead(userId: string, conversationId: string): Promise<void> {
    const room = await this.requireParticipantRoom(conversationId, userId);
    const changed = await this.messageRepository.markRoomRead(
      conversationId,
      userId,
    );
    // Opening a room always clears a manual "mark unread" and advances the
    // caller's read position, even when no unread messages were actually turned.
    await this.conversationRepository.upsertState(userId, conversationId, {
      markUnread: false,
      lastReadAt: new Date(),
    });
    if (changed > 0) {
      // Read receipt: tell the peer their messages in this room were read.
      this.realtime.emitToUser(
        this.peerOf(room, userId),
        RealtimeEvents.chatRead,
        {
          id: conversationId,
          at: new Date().toISOString(),
        },
      );
    }
  }

  /** Pin / mute / archive — per-user flags, upserted onto the caller's state.
   *  Only the fields present in `patch` change. Participant-gated. */
  async updateState(
    userId: string,
    conversationId: string,
    patch: Pick<ChatStatePatch, 'isPinned' | 'isMuted' | 'isArchived'>,
  ): Promise<void> {
    await this.requireParticipantRoom(conversationId, userId);
    await this.conversationRepository.upsertState(
      userId,
      conversationId,
      patch,
    );
  }

  /** "Mark as unread" — a UI flag the caller sets; cleared on next open. */
  async markUnread(userId: string, conversationId: string): Promise<void> {
    await this.requireParticipantRoom(conversationId, userId);
    await this.conversationRepository.upsertState(userId, conversationId, {
      markUnread: true,
    });
  }

  /** Delete-for-me: hides the room for the caller only, up to now. The peer is
   *  unaffected, and the room reappears if a newer message arrives. */
  async deleteForMe(userId: string, conversationId: string): Promise<void> {
    await this.requireParticipantRoom(conversationId, userId);
    await this.conversationRepository.upsertState(userId, conversationId, {
      deletedUntil: new Date(),
    });
  }

  async setBlocked(
    userId: string,
    conversationId: string,
    blocked: boolean,
  ): Promise<void> {
    const room = await this.requireParticipantRoom(conversationId, userId);
    const peerId = this.peerOf(room, userId);
    if (blocked) {
      await this.conversationRepository.block(userId, peerId);
    } else {
      await this.conversationRepository.unblock(userId, peerId);
    }
    void this.audit.record({
      actorId: userId,
      action: blocked ? ChatAuditAction.block : ChatAuditAction.unblock,
      entity: 'ChatRoom',
      entityId: conversationId,
      metadata: { peerId },
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

  private peerOf(room: ChatRoom, userId: string): string {
    return room.user1Id === userId ? room.user2Id : room.user1Id;
  }

  /** A human last-message preview: the text for TEXT, a type label for media
   *  (media messages often carry an empty caption). */
  private lastMessageLabel(message: ChatMessage): string {
    if (message.content.trim().length > 0) return message.content;
    switch (message.type) {
      case 'IMAGE':
        return '📷 Photo';
      case 'AUDIO':
        return '🎤 Voice message';
      case 'VIDEO':
        return '🎬 Video';
      default:
        return '';
    }
  }
}
