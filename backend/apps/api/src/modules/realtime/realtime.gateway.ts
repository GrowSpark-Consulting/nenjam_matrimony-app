import { Logger } from '@nestjs/common';
import {
  ConnectedSocket,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { FirebaseService } from '@app/firebase';
import { PrismaService } from '@app/database';
import { RedisService } from '@app/cache';
import { getCachedUserId, setCachedUserId } from '@app/common';
import { PresenceService } from './presence.service';
import {
  RealtimeEvent,
  RealtimeEvents,
  RealtimePayload,
  userRoom,
} from './realtime.events';

/** Per-socket state we attach after authenticating the handshake. */
interface AuthedSocketData {
  userId?: string;
}

/**
 * The single real-time delivery point. Every device authenticates its socket
 * with the same Firebase ID token the REST API uses, then joins a per-user
 * room; targeted delivery is `server.to(userRoom(userId)).emit(...)`, so an
 * event reaches only that user — across all their devices — and never anyone
 * else. Room membership (not a hand-rolled map) is the source of truth for
 * delivery, so multi-device and disconnect cleanup are handled by socket.io;
 * with the Redis adapter (see RedisIoAdapter) the same emit fans out across API
 * instances. Injected by the domain services, which call [emitToUser] only
 * AFTER their DB transaction commits.
 */
@WebSocketGateway({
  // Same permissive dev CORS as the HTTP app; a deployed origin allowlist
  // tightens both together.
  cors: { origin: true, credentials: true },
})
export class RealtimeGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  private readonly logger = new Logger(RealtimeGateway.name);

  @WebSocketServer()
  private server!: Server;

  constructor(
    private readonly firebase: FirebaseService,
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly presence: PresenceService,
  ) {}

  async handleConnection(client: Socket): Promise<void> {
    try {
      const token = this.extractToken(client);
      if (!token) return this.reject(client, 'Missing auth token.');

      const decoded = await this.firebase.verifyIdToken(token);
      const userId = await this.resolveUserId(decoded.uid);
      if (!userId) return this.reject(client, 'Unknown user.');

      (client.data as AuthedSocketData).userId = userId;
      await client.join(userRoom(userId));
      // Record this device in the (Redis-backed, cross-instance) presence set.
      await this.presence.touch(userId, client.id);
      this.logger.log(`Socket ${client.id} authenticated for user ${userId}.`);
      // Signal the client that the socket is fully authenticated and joined.
      // Clients should emit `chat.sync` (reconnect replay) on THIS event, not on
      // transport `connect`, which fires before this async auth completes.
      client.emit('ready');
    } catch (error) {
      this.reject(client, `Auth failed: ${(error as Error).message}`);
    }
  }

  handleDisconnect(client: Socket): void {
    const userId = (client.data as AuthedSocketData).userId;
    if (!userId) return;
    // socket.io already removed the socket from its room; drop this device from
    // presence too (best-effort — a leftover member ages out via the stale
    // window regardless).
    void this.presence.remove(userId, client.id);
  }

  /**
   * Presence heartbeat. The client emits `presence.ping` on an interval (see
   * PresenceService.HEARTBEAT_INTERVAL_MS) so a device that's connected but idle
   * keeps its presence fresh and doesn't age out of the stale window. Replies
   * `presence.pong` so the client can also use it as a liveness/RTT probe.
   */
  @SubscribeMessage('presence.ping')
  async handlePresencePing(@ConnectedSocket() client: Socket): Promise<void> {
    const userId = (client.data as AuthedSocketData).userId;
    if (!userId) return;
    await this.presence.touch(userId, client.id);
    client.emit('presence.pong', { at: Date.now() });
  }

  /**
   * Delivers an event to every device of one user. No-op if the socket server
   * isn't up yet or the user has no connected device (the event is just a
   * refresh signal — the client re-syncs via REST on next open regardless).
   */
  emitToUser(
    userId: string,
    event: RealtimeEvent,
    payload: RealtimePayload | Record<string, unknown>,
  ): void {
    if (!this.server) return;
    this.server.to(userRoom(userId)).emit(event, payload);
  }

  // ── internals ──────────────────────────────────────────────────────────

  private extractToken(client: Socket): string | null {
    const fromAuth = (client.handshake.auth?.token ?? '') as string;
    if (fromAuth) return fromAuth.replace(/^Bearer\s+/i, '').trim();
    const header = client.handshake.headers?.authorization ?? '';
    return header ? header.replace(/^Bearer\s+/i, '').trim() : null;
  }

  /** firebaseUid → internal user id, reusing the same short-lived cache the
   *  auth guard uses (fail-open to a single DB read). */
  private async resolveUserId(firebaseUid: string): Promise<string | null> {
    const cached = await getCachedUserId(this.redis, firebaseUid);
    if (cached) return cached;
    const user = await this.prisma.user.findUnique({
      where: { firebaseUid },
      select: { id: true },
    });
    if (user) await setCachedUserId(this.redis, firebaseUid, user.id);
    return user?.id ?? null;
  }

  private reject(client: Socket, reason: string): void {
    this.logger.warn(`Rejecting socket ${client.id}: ${reason}`);
    client.emit('unauthorized', { reason });
    client.disconnect(true);
  }

  /** Exposed so the constants stay the single source of event names. */
  static get events(): typeof RealtimeEvents {
    return RealtimeEvents;
  }
}
