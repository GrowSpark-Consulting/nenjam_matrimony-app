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
import { ConversationRepository } from '../repositories/conversation.repository';
import { MessageRepository } from '../repositories/message.repository';
import {
  ConversationDto,
  ConversationPageDto,
  GetOrCreateConversationResponseDto,
} from '../dto/conversation.response.dto';

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

    const peerIds = rooms.map((room) => this.peerOf(room, userId));
    const [unreadByRoom, blockedPeers, profileRows] = await Promise.all([
      this.conversationRepository.unreadCountsByRoom(
        userId,
        rooms.map((r) => r.id),
      ),
      this.conversationRepository.blockedPeerIds(userId, peerIds),
      this.conversationRepository.findFeedProfilesByUserIds([
        ...new Set(peerIds),
      ]),
    ]);
    const profileDtos = await this.profileMapper.toDtoList(profileRows);
    const profileByUserId = new Map(profileDtos.map((dto) => [dto.id, dto]));

    const items: ConversationDto[] = [];
    for (const room of rooms) {
      const peerId = this.peerOf(room, userId);
      const profile = profileByUserId.get(peerId);
      if (!profile) continue; // peer has no finalized profile — can't render
      const last = room.messages[0] as ChatMessage | undefined;
      const fromMe = last?.senderId === userId;
      items.push({
        id: room.id,
        profile,
        lastMessage: last ? this.lastMessageLabel(last) : '',
        lastMessageAt: (room.lastMessageAt ?? room.createdAt).toISOString(),
        unreadCount: unreadByRoom.get(room.id) ?? 0,
        lastMessageFromMe: Boolean(fromMe),
        isBlocked: blockedPeers.has(peerId),
        lastMessageStatus:
          last && fromMe ? (last.isRead ? 'read' : 'sent') : null,
        isPinned: false,
        isMuted: false,
        isArchived: false,
        isTyping: false,
        isLocked: false,
        smartIndicator: 'none',
      });
    }

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
      throw new ForbiddenException(
        'Users cannot message until interest is accepted.',
      );
    }

    const room = await this.prisma.$transaction((tx) =>
      this.conversationRepository.getOrCreate(tx, userId, peerId),
    );

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
