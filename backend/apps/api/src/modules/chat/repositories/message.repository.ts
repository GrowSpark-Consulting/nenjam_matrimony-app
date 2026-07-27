import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  ChatMessage,
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
}

@Injectable()
export class MessageRepository {
  constructor(private readonly prisma: PrismaService) {}

  create(
    client: PrismaClientLike,
    data: CreateMessageData,
  ): Promise<ChatMessage> {
    return client.chatMessage.create({
      data: {
        roomId: data.roomId,
        senderId: data.senderId,
        content: data.content,
        type: data.type,
        mediaUrl: data.mediaUrl ?? null,
      },
    });
  }

  /** Bumps the room's activity timestamp so it sorts to the top of the list —
   *  run in the same transaction as the message create. */
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

  /** One page of a room's messages, newest first (page 1 = newest slice), plus
   *  the total so the caller can compute `hasMore`. Excludes soft-deleted. */
  listPaged(
    roomId: string,
    skip: number,
    take: number,
  ): Promise<[ChatMessage[], number]> {
    const where: Prisma.ChatMessageWhereInput = { roomId, deletedAt: null };
    return this.prisma.$transaction([
      this.prisma.chatMessage.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take,
      }),
      this.prisma.chatMessage.count({ where }),
    ]);
  }

  /** Marks every message the OTHER participant sent in this room as read.
   *  Returns how many flipped (0 = nothing to do). */
  async markRoomRead(roomId: string, readerId: string): Promise<number> {
    const result = await this.prisma.chatMessage.updateMany({
      where: { roomId, senderId: { not: readerId }, isRead: false },
      data: { isRead: true, readAt: new Date() },
    });
    return result.count;
  }
}
