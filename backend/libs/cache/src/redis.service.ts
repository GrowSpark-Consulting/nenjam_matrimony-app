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
    } catch (error) {
      this.failStartup('Redis connection failed', error);
    }

    const start = Date.now();
    let pong: string;
    try {
      pong = await this.client.ping();
    } catch (error) {
      this.failStartup('Redis PING failed', error);
    }

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
  }

  async onModuleDestroy(): Promise<void> {
    await this.client.quit();
  }

  private failStartup(prefix: string, error: unknown): never {
    const cause = this.lastConnectionError ?? error;
    this.logger.error(`${prefix}: ${this.describeConnectionError(cause)}`);
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
