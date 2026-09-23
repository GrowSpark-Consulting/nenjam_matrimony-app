import { Logger } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
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
import {
  getCachedUserId,
  isAccountUsable,
  setCachedAuthUser,
} from '@app/common';
import { PresenceService } from './presence.service';
import { ActiveConversationService } from './active-conversation.service';
import {
  RealtimeEvent,
  RealtimeEvents,
  RealtimePayload,
  userRoom,
} from './realtime.events';

/** Per-socket state we attach after authenticating the handshake. */
interface AuthedSocketData {
  userId?: string;
  /** Kept so the heartbeat can re-check the account against the auth cache,
   *  which is keyed by Firebase UID. */
  firebaseUid?: string;
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
    private readonly activeConversation: ActiveConversationService,
  ) {}

  async handleConnection(client: Socket): Promise<void> {
    try {
      const token = this.extractToken(client);
      if (!token) return this.reject(client, 'Missing auth token.');

      const decoded = await this.firebase.verifyIdToken(token);
      const userId = await this.resolveUserId(decoded.uid);
      if (!userId) return this.reject(client, 'Unknown user.');

      const data = client.data as AuthedSocketData;
      data.userId = userId;
      data.firebaseUid = decoded.uid;
      await client.join(userRoom(userId));
      // Record this device. If the user had no other device online, this is an
      // offline→online transition worth telling their conversation peers about.
      const wasOnline = await this.presence.isOnline(userId);
      await this.presence.touch(userId, client.id);
      this.logger.log(`Socket ${client.id} authenticated for user ${userId}.`);
      // Signal the client that the socket is fully authenticated and joined.
      // Clients should emit `chat.sync` (reconnect replay) on THIS event, not on
      // transport `connect`, which fires before this async auth completes.
      client.emit('ready');
      if (!wasOnline) void this.broadcastPresence(userId, true, null);
    } catch (error) {
      this.reject(client, `Auth failed: ${(error as Error).message}`);
    }
  }

  async handleDisconnect(client: Socket): Promise<void> {
    const userId = (client.data as AuthedSocketData).userId;
    if (!userId) return;
    // Clear what this device had open first. A disconnected device must never
    // stay marked as viewing a conversation — that would silently suppress this
    // member's chat pushes until the entry aged out of the stale window.
    await this.activeConversation.leave(userId, client.id);
    // socket.io already removed the socket from its room; drop this device from
    // presence too. If it was the user's last device, tell their peers they're
    // now offline (with a fresh last-seen).
    await this.presence.remove(userId, client.id);
    const stillOnline = await this.presence.isOnline(userId);
    if (!stillOnline) await this.broadcastPresence(userId, false, new Date());
  }

  /**
   * Presence heartbeat. The client emits `presence.ping` on an interval (see
   * PresenceService.HEARTBEAT_INTERVAL_MS) so a device that's connected but idle
   * keeps its presence fresh and doesn't age out of the stale window. Replies
   * `presence.pong` so the client can also use it as a liveness/RTT probe.
   *
   * It is also where a socket learns it is no longer welcome. The handshake
   * check runs once, so without this a member banned mid-session kept a live
   * socket — still receiving chat messages and notification events — until they
   * happened to disconnect, however long that took. Re-checking here bounds
   * that to one heartbeat (~25s) plus the auth cache TTL, and costs nothing on
   * the normal path: a cache hit is one Redis read on a heartbeat that already
   * makes several.
   */
  @SubscribeMessage('presence.ping')
  async handlePresencePing(@ConnectedSocket() client: Socket): Promise<void> {
    const userId = (client.data as AuthedSocketData).userId;
    if (!userId) return;
    if (!(await this.stillAllowed(client))) {
      return this.rejectBlocked(client, userId);
    }
    // A heartbeat also re-establishes presence after an explicit background
    // (`presence.offline`) or a stale-window age-out, so detect that transition
    // and re-announce online to peers.
    const wasOnline = await this.presence.isOnline(userId);
    await this.presence.touch(userId, client.id);
    // Keep any open-conversation entry fresh on the same heartbeat, so a member
    // sitting in a chat never ages out of the stale window and starts receiving
    // pushes for the thread they are looking at. Costs no extra client traffic.
    await this.activeConversation.refresh(userId, client.id);
    client.emit('presence.pong', { at: Date.now() });
    if (!wasOnline) void this.broadcastPresence(userId, true, null);
  }

  /**
   * The client signals it's backgrounding (app paused). Mark the user offline
   * immediately — dropping all their devices and stamping last-seen — and tell
   * their peers, rather than waiting for each socket to disconnect or age out.
   * The next `presence.ping` (on resume) re-announces online.
   */
  @SubscribeMessage('presence.offline')
  async handlePresenceOffline(
    @ConnectedSocket() client: Socket,
  ): Promise<void> {
    const userId = (client.data as AuthedSocketData).userId;
    if (!userId) return;
    // Backgrounding means nothing is on screen — drop every device entry so the
    // member resumes getting chat pushes immediately rather than after the
    // stale window.
    await this.activeConversation.clearUser(userId);
    await this.presence.removeAll(userId);
    await this.broadcastPresence(userId, false, new Date());
  }

  /**
   * The device reports the conversation it now has on screen. Suppression is
   * scoped to exactly this thread — a member in a DIFFERENT conversation, or on
   * any other screen, keeps receiving pushes.
   *
   * Idempotent, and switching threads is just another call: one entry per
   * device, so the previous conversation stops suppressing the moment the
   * member moves on.
   */
  @SubscribeMessage(RealtimeEvents.chatViewing)
  async handleChatViewing(
    @ConnectedSocket() client: Socket,
    @MessageBody() payload: { conversationId?: unknown },
  ): Promise<void> {
    const userId = (client.data as AuthedSocketData).userId;
    if (!userId) return;
    const conversationId = payload?.conversationId;
    // Never trust the socket payload's shape. A malformed id is dropped rather
    // than stored, since a bad entry could only ever suppress a real push.
    if (typeof conversationId !== 'string' || conversationId.length === 0) {
      return;
    }
    await this.activeConversation.enter(userId, client.id, conversationId);
  }

  /** The device left the chat screen. Clears only this device's entry. */
  @SubscribeMessage(RealtimeEvents.chatStopViewing)
  async handleChatStopViewing(
    @ConnectedSocket() client: Socket,
  ): Promise<void> {
    const userId = (client.data as AuthedSocketData).userId;
    if (!userId) return;
    await this.activeConversation.leave(userId, client.id);
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

  /**
   * Announces a user's online/offline transition to everyone they share an
   * active conversation with — presence is only ever visible to conversation
   * peers, never broadcast globally. `lastSeenAt` is null when coming online.
   * Lives here (rather than the chat module) because it's driven by the socket
   * connection lifecycle this gateway owns; the peer lookup is a single indexed
   * query via the already-injected Prisma client, so no dependency on the chat
   * module — and thus no import cycle — is introduced.
   */
  private async broadcastPresence(
    userId: string,
    isOnline: boolean,
    lastSeenAt: Date | null,
  ): Promise<void> {
    const peerIds = await this.findConversationPeerIds(userId);
    if (peerIds.length === 0) return;
    const payload = {
      userId,
      isOnline,
      lastSeenAt: lastSeenAt ? lastSeenAt.toISOString() : null,
    };
    for (const peerId of peerIds) {
      this.emitToUser(peerId, RealtimeEvents.chatPresence, payload);
    }
  }

  /** The distinct other-participant ids across all of a user's active rooms. */
  private async findConversationPeerIds(userId: string): Promise<string[]> {
    const rooms = await this.prisma.chatRoom.findMany({
      where: { isActive: true, OR: [{ user1Id: userId }, { user2Id: userId }] },
      select: { user1Id: true, user2Id: true },
    });
    const peers = new Set<string>();
    for (const room of rooms) {
      peers.add(room.user1Id === userId ? room.user2Id : room.user1Id);
    }
    return [...peers];
  }

  private extractToken(client: Socket): string | null {
    const fromAuth = (client.handshake.auth?.token ?? '') as string;
    if (fromAuth) return fromAuth.replace(/^Bearer\s+/i, '').trim();
    const header = client.handshake.headers?.authorization ?? '';
    return header ? header.replace(/^Bearer\s+/i, '').trim() : null;
  }

  /** firebaseUid → internal user id, reusing the same short-lived cache the
   *  auth guard uses (fail-open to a single DB read).
   *
   *  Null for an account that may not use the API — suspended, banned,
   *  deactivated or soft-deleted — so a socket is refused on the same rule the
   *  HTTP guard applies. `getCachedUserId` already withholds those, so a
   *  blocked account cannot slip through on a cache hit either. */
  private async resolveUserId(firebaseUid: string): Promise<string | null> {
    const cached = await getCachedUserId(this.redis, firebaseUid);
    if (cached) return cached;
    const user = await this.prisma.user.findUnique({
      where: { firebaseUid },
      select: { id: true, status: true, deletedAt: true },
    });
    if (!user) return null;

    const account = {
      id: user.id,
      status: typeof user.status === 'string' ? user.status : '',
      deleted: user.deletedAt != null,
    };
    await setCachedAuthUser(this.redis, firebaseUid, account);
    return isAccountUsable(account) ? account.id : null;
  }

  /**
   * Whether this socket's account may still use the API, re-checked against the
   * same source the HTTP guard uses.
   *
   * Reads through the shared auth cache, so this is a Redis hit on the common
   * path and one indexed DB read once the entry expires — the same read the
   * member's next HTTP request would have made anyway. Fails OPEN on a socket
   * with no recorded uid (one authenticated before this field existed, mid
   * deploy): those keep working until they reconnect, exactly as before.
   */
  private async stillAllowed(client: Socket): Promise<boolean> {
    const { firebaseUid } = client.data as AuthedSocketData;
    if (!firebaseUid) return true;
    return (await this.resolveUserId(firebaseUid)) !== null;
  }

  /** Disconnects a socket whose account was suspended, banned, deactivated or
   *  deleted after it connected, clearing its presence so peers stop seeing the
   *  member as online. */
  private async rejectBlocked(client: Socket, userId: string): Promise<void> {
    await this.activeConversation.leave(userId, client.id);
    await this.presence.removeAll(userId);
    await this.broadcastPresence(userId, false, new Date());
    this.reject(client, 'Account is no longer active.');
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
