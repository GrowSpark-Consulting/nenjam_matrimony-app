import { Injectable } from '@nestjs/common';
import { RedisService } from './redis.service';

export interface RedisHealth {
  status: 'up' | 'down';
  latencyMs?: number;
  ping?: string;
  error?: string;
}

@Injectable()
export class RedisHealthService {
  constructor(private readonly redisService: RedisService) {}

  async check(): Promise<RedisHealth> {
    const start = Date.now();

    try {
      const pong = await this.redisService.getClient().ping();
      return { status: 'up', latencyMs: Date.now() - start, ping: pong };
    } catch (error) {
      return {
        status: 'down',
        error: error instanceof Error ? error.message : 'Unknown Redis error',
      };
    }
  }
}
