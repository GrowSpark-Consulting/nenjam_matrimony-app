import { Injectable } from '@nestjs/common';
import { RedisService } from '@app/cache';

/**
 * A monotonic counter per member, bumped whenever something changes that could
 * alter what their Discover feed contains or how it is ordered.
 *
 * Why a version and not just the WebSocket event: sockets are best-effort. A
 * member on a train loses the connection, misses the `feed.invalidate`, and
 * comes back to a feed built from preferences they changed ten minutes ago.
 * The version travels on every feed response, so a client holding a stale one
 * can notice on its own and refetch — the socket makes that fast, the version
 * makes it correct.
 *
 * It also gives cursor paging a safety check. A cursor is only meaningful
 * against the ordering that produced it; if the version moved, the client
 * knows its cursor describes a feed that no longer exists and should restart
 * rather than page into a shifted set.
 *
 * Deliberately NOT stored in Postgres. It changes on every profile edit, has
 * no historical value, and is worthless the moment it is stale — exactly the
 * shape of data that belongs in Redis. A member whose version is lost to an
 * eviction simply gets a fresh feed.
 */
export function feedVersionKey(userId: string): string {
  return `feed:version:${userId}`;
}

@Injectable()
export class FeedVersionService {
  constructor(private readonly redis: RedisService) {}

  /**
   * The member's current feed version. Returns 0 when Redis is unavailable —
   * a stable value the client can compare against, rather than an error or a
   * number that changes on every request and triggers endless refetching.
   */
  async get(userId: string): Promise<number> {
    const client = this.redis.getClient();
    if (client.status !== 'ready') return 0;
    try {
      const raw = await client.get(feedVersionKey(userId));
      const n = Number(raw);
      return Number.isFinite(n) && n > 0 ? n : 0;
    } catch {
      return 0;
    }
  }

  /**
   * Bumps the version and returns the new value.
   *
   * INCR is atomic, so two concurrent mutations cannot land on the same
   * number — which matters, because a client comparing versions would
   * otherwise conclude nothing had changed.
   *
   * Never throws: a failed bump means the client relies on the TTL-bounded
   * caches instead, which is a far better outcome than a profile save that
   * fails because Redis blinked.
   */
  async bump(userId: string): Promise<number> {
    const client = this.redis.getClient();
    if (client.status !== 'ready') return 0;
    try {
      return await client.incr(feedVersionKey(userId));
    } catch {
      return 0;
    }
  }
}
