import { Injectable, Logger } from '@nestjs/common';
import { RedisService } from '@app/cache';
import { FeedRepository, type SelfProfile } from '../repositories/feed.repository';
import {
  PreferenceRepository,
  type PartnerPreferenceRow,
} from '../repositories/preference.repository';

/**
 * The seeker's own profile and saved preference, cached together.
 *
 * These two rows are read on every feed and search request, are loaded in
 * parallel as one round trip, and change only when the member edits their
 * profile or preferences. Serving them from Redis removes that round trip
 * entirely — one of the four sequential trips a warm feed request makes.
 *
 * What is deliberately NOT in here, and why it matters: nothing
 * safety-critical. Block relationships, account status and `deletedAt` stay
 * out, so they continue to be evaluated against the live database inside
 * `buildFeedWhere` on every single request. A member blocked one second ago is
 * excluded from the next request regardless of this cache. The cache holds
 * only the seeker's own attributes and their stated preferences — data whose
 * worst-case staleness is a slightly out-of-date ordering, never a candidate
 * who should have been filtered out.
 */
export interface FeedSeekerContext {
  self: SelfProfile | null;
  pref: PartnerPreferenceRow | null;
}

/**
 * 5 minutes.
 *
 * Chosen from how these rows actually change. A member edits their profile or
 * preferences rarely — and when they do, the write paths invalidate this key
 * explicitly (see FeedContextInvalidator), so the TTL is a backstop rather
 * than the primary correctness mechanism. It exists to bound staleness from
 * anything that mutates these rows without going through those paths: an admin
 * action, a script, a future endpoint someone forgets to wire up.
 *
 * Shorter would cost round trips for no benefit given explicit invalidation.
 * Much longer would make an unnoticed missing invalidation hurt for an hour
 * instead of five minutes.
 */
export const FEED_CONTEXT_CACHE_TTL_SECONDS = 300;

export function feedContextKey(userId: string): string {
  return `feed:context:${userId}`;
}

@Injectable()
export class FeedContextService {
  private readonly logger = new Logger(FeedContextService.name);

  constructor(
    private readonly redis: RedisService,
    private readonly feedRepository: FeedRepository,
    private readonly preferenceRepository: PreferenceRepository,
  ) {}

  /**
   * Cache-first, database-authoritative.
   *
   * Redis is an optimisation here and never a dependency: every failure path —
   * client not ready, GET throwing, malformed payload, SET throwing — falls
   * through to the same database read the code did before this cache existed.
   * A member must never see an error because Redis is having a bad minute.
   */
  async load(userId: string): Promise<FeedSeekerContext> {
    const cached = await this.read(userId);
    if (cached) return cached;

    // MISS (or Redis unavailable) — the original two-query parallel load.
    const [self, pref] = await Promise.all([
      this.feedRepository.findSelf(userId),
      this.preferenceRepository.findByUserId(userId),
    ]);
    const context: FeedSeekerContext = { self, pref };

    // Only cache a real profile. Caching "no profile yet" would keep a member
    // who has just finished registration out of their own feed for the TTL.
    if (self) void this.write(userId, context);
    return context;
  }

  /** Drops the cached context. Called after a write that affects matching. */
  invalidate(userId: string): Promise<void> {
    return invalidateFeedContext(this.redis, userId);
  }

  // ── internals ──────────────────────────────────────────────────────────

  private async read(userId: string): Promise<FeedSeekerContext | null> {
    const client = this.redis.getClient();
    if (client.status !== 'ready') return null;
    try {
      const raw = await client.get(feedContextKey(userId));
      if (!raw) return null;
      return this.revive(JSON.parse(raw) as FeedSeekerContext);
    } catch {
      // A miss, a Redis error and a corrupt payload are all the same thing to
      // the caller: fall through to the database. Deliberately not logged —
      // this runs on every request, and a log line per miss is noise.
      return null;
    }
  }

  private async write(userId: string, context: FeedSeekerContext): Promise<void> {
    const client = this.redis.getClient();
    if (client.status !== 'ready') return;
    try {
      await client.set(
        feedContextKey(userId),
        JSON.stringify(context),
        'EX',
        FEED_CONTEXT_CACHE_TTL_SECONDS,
      );
    } catch {
      // Non-fatal — the request already has its data.
    }
  }

  /**
   * JSON has no Date type, so `dob`, `updatedAt` and the preference
   * timestamps come back as strings. Scoring does date arithmetic on them
   * (age, activity decay), and `new Date(string)` would work by accident while
   * `instanceof Date` checks would not — so they are restored explicitly
   * rather than left as a shape that only mostly behaves like the DB row.
   */
  private revive(context: FeedSeekerContext): FeedSeekerContext {
    const toDate = (v: unknown): Date | null => {
      if (v instanceof Date) return v;
      if (typeof v === 'string') {
        const d = new Date(v);
        return Number.isNaN(d.getTime()) ? null : d;
      }
      return null;
    };

    const self = context.self
      ? ({
          ...context.self,
          dob: toDate((context.self as { dob?: unknown }).dob),
          updatedAt: toDate((context.self as { updatedAt?: unknown }).updatedAt),
        } as SelfProfile)
      : null;

    return { self, pref: context.pref ?? null };
  }
}

/**
 * Drops a member's cached feed context.
 *
 * A plain function rather than a method so write paths in other modules can
 * call it with the global RedisService alone, without importing MatchesModule
 * — the same shape as `invalidateCachedUserId` in libs/common/src/auth. Never
 * throws: a failed invalidation is bounded by the TTL, and turning a
 * successful profile save into an error because Redis blinked would be a far
 * worse outcome than a few minutes of slightly stale ordering.
 */
export async function invalidateFeedContext(
  redis: RedisService,
  userId: string,
): Promise<void> {
  const client = redis.getClient();
  if (client.status !== 'ready') return;
  try {
    await client.del(feedContextKey(userId));
  } catch {
    // Non-fatal — bounded by FEED_CONTEXT_CACHE_TTL_SECONDS.
  }
}
