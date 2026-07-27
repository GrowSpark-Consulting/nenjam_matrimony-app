import {
  ConnectedSocket,
  MessageBody,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { RealtimeEvents, userRoom } from '../../realtime/realtime.events';
import { ConversationRepository } from '../repositories/conversation.repository';
import { MessageRepository } from '../repositories/message.repository';
import { MessagesService } from '../services/messages.service';

interface TypingPayload {
  roomId?: string;
  isTyping?: boolean;
}

// Ignore typing events fired more often than this per socket+room — a cheap
// anti-flood throttle on top of the client's own start/stop debouncing.
const TYPING_THROTTLE_MS = 800;

/**
 * Chat's client→server socket handler: typing indicators. Shares the same
 * authenticated socket.io connection as RealtimeGateway (which verified the
 * Firebase token and set `client.data.userId` on connect) — this only reads
 * that identity, never re-authenticates. A typing event is forwarded ONLY to
 * the room's other participant, and ONLY if the sender is actually in the room
 * (authorization, not just UI). Message/read events go the other direction and
 * are emitted server-side via RealtimeGateway.
 */
@WebSocketGateway({ cors: { origin: true, credentials: true } })
export class ChatGateway {
  @WebSocketServer()
  private server!: Server;

  private readonly lastTypingAt = new Map<string, number>();

  constructor(
    private readonly conversationRepository: ConversationRepository,
    private readonly messageRepository: MessageRepository,
    private readonly messagesService: MessagesService,
  ) {}

  /**
   * Reconnect replay. The client emits `chat.sync` after (re)connecting; the
   * server delivers every message that arrived while it was offline (status
   * still SENT), promotes those to DELIVERED, and notifies each sender via
   * `chat.delivered`. This is how a client that missed live pushes catches up
   * without a manual refresh, and how delivery receipts converge after an
   * offline stretch. Idempotent — messages already delivered are skipped, and a
   * re-emitted message is deduped by id on the client.
   */
  @SubscribeMessage('chat.sync')
  async handleSync(@ConnectedSocket() client: Socket): Promise<void> {
    const userId = (client.data as { userId?: string }).userId;
    if (!userId) return;

    const undelivered =
      await this.messageRepository.findUndeliveredForUser(userId);
    if (undelivered.length === 0) return;

    await this.messageRepository.markDelivered(undelivered.map((m) => m.id));
    const now = new Date();

    for (const message of undelivered) {
      message.status = 'DELIVERED';
      message.deliveredAt = now;
      const dto = await this.messagesService.toDto(message, userId);
      this.server.to(userRoom(userId)).emit(RealtimeEvents.chatMessage, {
        ...dto,
      });
      this.server
        .to(userRoom(message.senderId))
        .emit(RealtimeEvents.chatDelivered, {
          id: message.id,
          roomId: message.roomId,
          at: now.toISOString(),
        });
    }
  }

  @SubscribeMessage(RealtimeEvents.chatTyping)
  async handleTyping(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: TypingPayload,
  ): Promise<void> {
    const userId = (client.data as { userId?: string }).userId;
    const roomId = body?.roomId;
    if (!userId || !roomId) return;

    if (this.isThrottled(client.id, roomId)) return;

    const room = await this.conversationRepository.findById(roomId);
    if (!room) return;
    if (room.user1Id !== userId && room.user2Id !== userId) return; // not a participant

    const peerId = room.user1Id === userId ? room.user2Id : room.user1Id;
    this.server.to(userRoom(peerId)).emit(RealtimeEvents.chatTyping, {
      roomId,
      isTyping: Boolean(body.isTyping),
    });
  }

  private isThrottled(socketId: string, roomId: string): boolean {
    const key = `${socketId}:${roomId}`;
    const now = Date.now();
    const last = this.lastTypingAt.get(key) ?? 0;
    if (now - last < TYPING_THROTTLE_MS) return true;
    this.lastTypingAt.set(key, now);
    return false;
  }
}
