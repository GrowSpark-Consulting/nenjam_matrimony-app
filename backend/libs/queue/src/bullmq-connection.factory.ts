import type { ConnectionOptions } from 'bullmq';
import { AppConfigService } from '@app/config';

/**
 * Builds the Redis connection BullMQ should use.
 *
 * Deliberately NOT the shared `REDIS_CLIENT` from `@app/cache`. That client is
 * tuned for request-path caching — `maxRetriesPerRequest: 1` and a capped
 * `retryStrategy` — so a brief blip fails fast rather than stalling an HTTP
 * request. BullMQ requires the opposite: its workers hold long-lived blocking
 * reads (BRPOPLPUSH/XREAD), and ioredis throws
 * "Cannot use a connection with maxRetriesPerRequest set" unless that option
 * is null. Sharing one client would either break the queue or make the cache
 * hang, so each gets its own connection against the same Redis instance.
 */
export function buildBullMqConnection(
  configService: AppConfigService,
): ConnectionOptions {
  const { url, host, port, username, password, db } = configService.redis;

  // Required by BullMQ for blocking commands; see note above.
  const required = { maxRetriesPerRequest: null } as const;

  if (url) {
    const parsed = new URL(url);
    return {
      host: parsed.hostname,
      port: parsed.port ? Number(parsed.port) : 6379,
      username: parsed.username || undefined,
      password: parsed.password || undefined,
      // rediss:// means TLS. ioredis infers this when handed a URL string,
      // but BullMQ takes a structured options object, so it must be explicit.
      tls: parsed.protocol === 'rediss:' ? {} : undefined,
      ...required,
    };
  }

  return { host, port, username, password, db, ...required };
}
