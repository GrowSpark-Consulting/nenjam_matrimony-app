import { Injectable, Logger } from '@nestjs/common';
import { RedisService } from '@app/cache';
import { RealtimeGateway } from '../../realtime/realtime.gateway';
import { RealtimeEvents } from '../../realtime/realtime.events';
import { invalidateFeedContext } from './feed-context.cache';
import { FeedVersionService } from './feed-version.cache';

/**
 * One call for "this member's feed is no longer accurate".
 *
 * Three things have to happen together and in this order, and doing them by
 * hand at each call site is how they drift apart:
 *
 *   1. Drop the cached seeker context, so the next request rebuilds from the
 *      database rather than the pre-change rows.
 *   2. Bump the feed version, so a client holding an old one can tell.
 *   3. Emit `feed.invalidate`, so it finds out now rather than on next open.
 *
 * The order matters. Clearing the cache first means that by the time the
 * client reacts to the event, a refetch already returns fresh data — bumping
 * or emitting first would open a window where an eager client refetches and
 * gets served the stale cache it was just told to discard.
 *
 * Everything here is best-effort and non-throwing. This runs after a
 * successful database write, and the write is the source of truth: a member's
 * profile save must not fail because Redis or a socket had a bad moment. The
 * worst case is a feed that stays stale until the 300-second context TTL
 * expires.
 */
@Injectable()
export class FeedInvalidationService {
  private readonly logger = new Logger(FeedInvalidationService.name);

  constructor(
    private readonly redis: RedisService,
    private readonly version: FeedVersionService,
    private readonly realtime: RealtimeGateway,
  ) {}

  /**
   * @param userId  whose feed is now stale
   * @param reason  machine-readable, for the client to log or branch on
   */
  async invalidate(userId: string, reason: FeedInvalidationReason): Promise<void> {
    try {
      await invalidateFeedContext(this.redis, userId);
      const version = await this.version.bump(userId);

      // Emitting is deliberately last and deliberately not awaited beyond the
      // synchronous call: Socket.IO delivery is fire-and-forget, and a member
      // with no open socket is the normal case, not an error.
      this.realtime.emitToUser(userId, RealtimeEvents.feedInvalidate, {
        version,
        reason,
        at: new Date().toISOString(),
      });
    } catch (error) {
      // Never propagate — the database write already succeeded and is what
      // matters. Logged at debug because a Redis blip here is recoverable and
      // this path can run on every profile save.
      this.logger.debug(
        `Feed invalidation failed for ${userId} (${reason}): ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  /**
   * A block changes BOTH members' feeds — the blocker stops seeing the
   * blocked, and the blocked stops seeing the blocker. Invalidating only the
   * actor would leave the other side's cached context and version untouched,
   * so their feed would keep claiming to be current while silently containing
   * someone it should not.
   *
   * Note the cached context itself holds no block data — blocks are always
   * evaluated live in buildFeedWhere — so this is about the version and the
   * event, not about correctness of the filter.
   */
  async invalidatePair(
    userIdA: string,
    userIdB: string,
    reason: FeedInvalidationReason,
  ): Promise<void> {
    await Promise.all([
      this.invalidate(userIdA, reason),
      this.invalidate(userIdB, reason),
    ]);
  }
}

/**
 * Why a feed became stale. Kept to changes that actually affect what a
 * specific member sees.
 *
 * Deliberately absent: "a new member joined". Every new signup technically
 * changes everyone's potential feed, but emitting to the whole userbase on
 * every registration is a broadcast storm that buys nothing — the next
 * ordinary feed request picks new members up anyway.
 */
export type FeedInvalidationReason =
  | 'profile_updated'
  | 'preferences_updated'
  | 'psychology_updated'
  | 'block_created'
  | 'block_removed';
