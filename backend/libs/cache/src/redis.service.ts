import {
  Inject,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import type Redis from 'ioredis';
import { AppConfigService } from '@app/config';
import { REDIS_CLIENT } from './redis.constants';

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);

  // ioredis only surfaces the real failure reason (code, message) via the
  // 'error' event — the promise returned by connect()/ping() rejects with a
  // generic "Connection is closed." error carrying no diagnostic info at all.
  // Verified empirically; both are captured here so real errors aren't lost.
  private lastConnectionError?: Error;

  constructor(
    @Inject(REDIS_CLIENT) private readonly client: Redis,
    private readonly configService: AppConfigService,
  ) {
    this.client.on('error', (error: Error) => {
      this.lastConnectionError = error;
    });
  }

  getClient(): Redis {
    return this.client;
  }

  async onModuleInit(): Promise<void> {
    try {
      await this.client.connect();

      const start = Date.now();
      const pong = await this.client.ping();
      const latencyMs = Date.now() - start;
      const { host, port } = this.configService.redis;

      this.logger.log(
        [
          '=====================================',
          'REDIS',
          '',
          `Host        : ${host}`,
          `Port        : ${port}`,
          `Connection  : ${pong === 'PONG' ? 'SUCCESS' : 'FAILED'}`,
          `Latency     : ${latencyMs} ms`,
          '',
          '=====================================',
        ].join('\n'),
      );
    } catch (error) {
      this.handleStartupFailure(error);
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.client.quit();
  }

  // In development, Redis is a nice-to-have (caching/rate-limiting), not a
  // hard dependency — a developer without it running locally shouldn't be
  // blocked from starting the API. Production keeps the original
  // fail-fast behavior: a misconfigured/unreachable Redis there is a real
  // incident, not something to silently continue past.
  private handleStartupFailure(error: unknown): void {
    const cause = this.lastConnectionError ?? error;
    const description = this.describeConnectionError(cause);

    if (this.configService.isDevelopment) {
      this.logger.warn(
        `Redis unavailable — continuing without it (development only): ${description}`,
      );
      return;
    }

    this.logger.error(`Redis connection failed: ${description}`);
    throw cause;
  }

  private describeConnectionError(error: unknown): string {
    const err = error as { code?: string; message?: string } | undefined;
    const code = err?.code;
    const message = err?.message ?? String(error);
    const { host, port } = this.configService.redis;

    switch (code) {
      case 'ECONNREFUSED':
        return `Redis is unreachable at ${host}:${port}. Is Redis running?`;
      case 'ENOTFOUND':
        return `Invalid Redis host "${host}". DNS lookup failed.`;
      case 'ETIMEDOUT':
        return `Connection to Redis at ${host}:${port} timed out.`;
    }
    if (message.includes('NOAUTH') || message.includes('WRONGPASS')) {
      return 'Redis authentication failed. Check REDIS_PASSWORD.';
    }
    return message || 'Unknown Redis connection error.';
  }
}
