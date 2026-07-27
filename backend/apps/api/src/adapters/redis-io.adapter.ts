import { INestApplicationContext, Logger } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import type { Server, ServerOptions } from 'socket.io';
import { RedisService } from '@app/cache';

/**
 * socket.io adapter backed by Redis pub/sub so a `server.to(room).emit(...)`
 * from ANY API instance is delivered to that room's sockets on EVERY instance —
 * the piece that lets real-time delivery survive horizontal scaling (the
 * "10k+ concurrent, multiple instances" requirement) with no app-code change.
 *
 * Degrades gracefully: if Redis isn't reachable (e.g. local dev without Redis),
 * [connect] is a no-op and socket.io uses its default in-memory adapter — the
 * gateway still works for a single instance. Call [connect] before
 * `useWebSocketAdapter`.
 */
export class RedisIoAdapter extends IoAdapter {
  private readonly logger = new Logger(RedisIoAdapter.name);
  private adapterConstructor?: ReturnType<typeof createAdapter>;

  constructor(
    app: INestApplicationContext,
    private readonly redis: RedisService,
  ) {
    super(app);
  }

  async connect(): Promise<void> {
    const base = this.redis.getClient();
    if (base.status !== 'ready') {
      this.logger.warn(
        'Redis not ready — WebSocket using in-memory adapter (single-instance only).',
      );
      return;
    }
    try {
      const pubClient = base.duplicate();
      const subClient = base.duplicate();
      await Promise.all([pubClient.connect(), subClient.connect()]);
      this.adapterConstructor = createAdapter(pubClient, subClient);
      this.logger.log(
        'WebSocket Redis adapter connected (multi-instance ready).',
      );
    } catch (error) {
      this.logger.warn(
        `WebSocket Redis adapter unavailable, falling back to in-memory: ${(error as Error).message}`,
      );
    }
  }

  createIOServer(port: number, options?: ServerOptions): Server {
    const server = super.createIOServer(port, options) as Server;
    if (this.adapterConstructor) server.adapter(this.adapterConstructor);
    return server;
  }
}
