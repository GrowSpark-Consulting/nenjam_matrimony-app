import { Injectable } from '@nestjs/common';
import { RedisService } from '@app/cache';

/**
 * Remembers who a member has recently been shown, so the same faces don't fill
 * every tab.
 *
 * Daily, New, My Matches and More Matches all draw from one eligible pool. A
 * strong candidate scores well in all of them, so without this a member opens
 * four tabs and sees the same six people four times.
 *
 * Three deliberate properties:
 *
 *  SUPPRESS, NEVER EXCLUDE. Seen candidates are pushed to the back of the
 *  ranking, not filtered out. A permanent exclusion would mean one distracted
 *  scroll past someone removes them from that member's feed forever — and in a
 *  matrimony app, where the eligible pool for a given member is often small,
 *  that quietly empties the product.
 *
 *  BOUNDED. A sorted set trimmed to MAX_SEEN entries, so a heavy user cannot
 *  grow this key without limit. Redis on this project runs `volatile-lru`, and
 *  an unbounded key is exactly what makes an eviction policy start deleting
 *  things that matter.
 *
 *  EXPIRING. The whole key has a TTL, so a member who returns after a break
 *  gets a clean slate rather than a feed shaped by what they looked at weeks
 *  ago.
 */
export const FEED_SEEN_TTL_SECONDS = 7 * 24 * 3600; // 7 days
export const FEED_SEEN_MAX = 500;

export function feedSeenKey(userId: string): string {
  return `feed:seen:${userId}`;
}

@Injectable()
export class FeedSeenService {
  constructor(private readonly redis: RedisService) {}

  /**
   * The candidate ids this member has recently been shown.
   * Returns an empty set when Redis is unavailable — the feed then simply
   * doesn't de-duplicate, which is a far better failure than not loading.
   */
  async get(userId: string): Promise<Set<string>> {
    const client = this.redis.getClient();
    if (client.status !== 'ready') return new Set();
    try {
      const ids = await client.zrange(feedSeenKey(userId), 0, -1);
      return new Set(ids);
    } catch {
      return new Set();
    }
  }

  /**
   * Records the page just served. Scored by timestamp so the oldest entries
   * are the ones trimmed away.
   *
   * Fire-and-forget by design: the response has already been assembled, and
   * making a member wait on a bookkeeping write — or fail because of one —
   * would be the wrong trade.
   */
  async record(userId: string, candidateIds: string[]): Promise<void> {
    if (candidateIds.length === 0) return;
    const client = this.redis.getClient();
    if (client.status !== 'ready') return;
    try {
      const key = feedSeenKey(userId);
      const now = Date.now();
      const members = candidateIds.flatMap((id) => [now, id] as [number, string]);
      await client
        .multi()
        .zadd(key, ...(members as unknown as string[]))
        // Keep the newest FEED_SEEN_MAX by rank; drop everything older.
        .zremrangebyrank(key, 0, -(FEED_SEEN_MAX + 1))
        .expire(key, FEED_SEEN_TTL_SECONDS)
        .exec();
    } catch {
      // Non-fatal — the worst case is a repeated profile.
    }
  }

  /** Clears the history. Used when a member explicitly asks for a fresh feed. */
  async clear(userId: string): Promise<void> {
    const client = this.redis.getClient();
    if (client.status !== 'ready') return;
    try {
      await client.del(feedSeenKey(userId));
    } catch {
      // Non-fatal.
    }
  }
}
