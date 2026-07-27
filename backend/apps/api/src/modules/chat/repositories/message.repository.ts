import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  ChatMessage,
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
        clientMessageId: data.clientMessageId ?? null,
        status: data.status,
        deliveredAt: data.deliveredAt ?? null,
      },
    });
  }

  /** Idempotency lookup — the existing message for this sender's client key, if
   *  a retried send already created it. */
  findByClientKey(
    senderId: string,
    clientMessageId: string,
  ): Promise<ChatMessage | null> {
    return this.prisma.chatMessage.findUnique({
      where: { senderId_clientMessageId: { senderId, clientMessageId } },
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
  findUndeliveredForUser(userId: string): Promise<ChatMessage[]> {
    return this.prisma.chatMessage.findMany({
      where: {
        status: 'SENT',
        senderId: { not: userId },
        deletedAt: null,
        room: { is: { OR: [{ user1Id: userId }, { user2Id: userId }] } },
      },
      orderBy: { createdAt: 'asc' },
      take: 200,
    });
  }

  /** Flips SENT→DELIVERED for a set of messages. Returns rows changed. */
  async markDelivered(ids: string[]): Promise<number> {
    if (ids.length === 0) return 0;
    const result = await this.prisma.chatMessage.updateMany({
      where: { id: { in: ids }, status: 'SENT' },
      data: { status: 'DELIVERED', deliveredAt: new Date() },
    });
    return result.count;
  }
}
