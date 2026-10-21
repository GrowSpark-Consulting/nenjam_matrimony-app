import type { IncomingMessage } from 'node:http';
import { INestApplicationContext, Logger } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import type { Redis } from 'ioredis';
import type { Server, ServerOptions } from 'socket.io';
import { RedisService } from '@app/cache';
import {
  corsOriginOption,
  isOriginAllowed,
  type OriginPolicy,
} from './cors-origin';

// Bound the initial connect so a hung/blackholed Redis can never stall boot —
// on timeout we simply degrade to the in-memory adapter.
const CONNECT_TIMEOUT_MS = 5000;

/**
 * socket.io adapter backed by Redis pub/sub so a `server.to(room).emit(...)`
 * from ANY API instance is delivered to that room's sockets on EVERY instance —
 * the piece that lets real-time delivery survive horizontal scaling (the
 * "10k+ concurrent, multiple instances" requirement) with no app-code change.
 *
 * Degrades gracefully: if Redis isn't reachable (e.g. local dev without Redis),
 * [connect] falls back to socket.io's default in-memory adapter and the gateway
 * still works for a single instance. Call [connect] before `useWebSocketAdapter`.
 */
export class RedisIoAdapter extends IoAdapter {
  private readonly logger = new Logger(RedisIoAdapter.name);
  private adapterConstructor?: ReturnType<typeof createAdapter>;
  private pubClient?: Redis;
  private subClient?: Redis;

  constructor(
    app: INestApplicationContext,
    private readonly redis: RedisService,
    private readonly originPolicy: OriginPolicy,
  ) {
    super(app);
  }

  async connect(): Promise<void> {
    // Connect a dedicated pub/sub pair for the adapter. We deliberately do NOT
    // gate on the base client's `status`: this runs at bootstrap, BEFORE
    // `app.init()`, whereas the base client only connects later in
    // RedisService.onModuleInit — so a `status === 'ready'` check here would
    // always be false and wrongly fall back to the in-memory adapter even when
    // Redis is perfectly reachable. `duplicate()` clones the same connection
    // options (host / REDIS_URL / TLS); the override below gives these
    // long-lived infra clients a persistent reconnect policy (the base client's
    // strategy gives up after 3 tries — right for the cache, wrong for the
    // adapter, which must survive a transient Redis blip and resume fan-out).
    const pubClient = this.redis.getClient().duplicate({
      // Never stop reconnecting; back off up to 5s.
      retryStrategy: (times: number) => Math.min(times * 200, 5000),
      // Queue commands across a reconnect instead of failing them.
      maxRetriesPerRequest: null,
    });
    const subClient = pubClient.duplicate();
    try {
      await this.withTimeout(
        Promise.all([pubClient.connect(), subClient.connect()]),
        CONNECT_TIMEOUT_MS,
      );
      this.pubClient = pubClient;
      this.subClient = subClient;
      this.adapterConstructor = createAdapter(pubClient, subClient);
      this.logger.log(
        'WebSocket Redis adapter connected (multi-instance ready).',
      );
    } catch (error) {
      this.logger.warn(
        `WebSocket Redis adapter unavailable — using in-memory (single-instance only): ${(error as Error).message}`,
      );
      // Don't leave orphaned clients reconnecting in the background.
      pubClient.disconnect();
      subClient.disconnect();
    }
  }

  createIOServer(port: number, options?: ServerOptions): Server {
    const policy = this.originPolicy;
    const serverOptions: Partial<ServerOptions> = {
      ...options,
      // The same allowlist as the HTTP layer. Authentication is a Firebase ID
      // token in the handshake, never a cookie, so credentialed cross-origin
      // requests are not needed and not enabled.
      cors: { origin: corsOriginOption(policy), credentials: false },
      // The CORS headers above only govern long-polling. A browser's WebSocket
      // upgrade ignores them, so the Origin header is checked here for every
      // handshake, whatever the transport.
      allowRequest: (req: IncomingMessage, callback) =>
        callback(null, isOriginAllowed(req.headers.origin, policy)),
    };
    const server = super.createIOServer(port, serverOptions) as Server;
    if (this.adapterConstructor) server.adapter(this.adapterConstructor);
    return server;
  }

  /** Release the adapter's Redis pub/sub connections on app shutdown so they
   *  don't linger (or keep reconnecting) after the server closes. */
  async close(server: Server): Promise<void> {
    await super.close(server);
    // quit() drains in flight commands then closes; allSettled so one failing
    // never masks the other and shutdown always proceeds.
    await Promise.allSettled([this.pubClient?.quit(), this.subClient?.quit()]);
    this.pubClient = undefined;
    this.subClient = undefined;
  }

  private withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
    let timer: ReturnType<typeof setTimeout>;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(
        () => reject(new Error(`Redis connect timed out after ${ms}ms`)),
        ms,
      );
    });
    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
  }
}
