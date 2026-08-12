/**
 * Rate-limit policy for the public API.
 *
 * The API previously had no HTTP rate limiting at all. For a matrimony
 * platform that is mostly a scraping problem rather than a DoS one: every
 * member's profile, photos and location sit behind endpoints that would happily
 * serve a script twenty thousand times in a row. The socket layer already had
 * per-room throttling (ChatGateway.isThrottled); this is the equivalent for
 * REST.
 *
 * Three named tiers rather than one global number, because the endpoints differ
 * by an order of magnitude in how often legitimate use hits them:
 *
 *   default  — everything. Generous enough that normal app use never notices;
 *              a scraper walking the feed hits it in seconds.
 *   read     — high-frequency reads a real session genuinely repeats
 *              (opening profiles, paging the feed).
 *   write    — state-changing actions where abuse is the point: sending
 *              interests, uploading photos, reporting. Deliberately tight.
 *
 * Limits are per client IP. Two consequences worth knowing:
 *
 *   - Behind a proxy (Railway, any load balancer) Express must be told to
 *     trust it, or every request appears to come from the proxy's single IP
 *     and the whole userbase shares one bucket. main.ts sets `trust proxy`.
 *   - Counters are per-process and in-memory. With N API replicas the
 *     effective limit is N times these numbers. That is a real weakening, but
 *     still bounded — and it avoids making the rate limiter depend on Redis
 *     being reachable, which would turn a cache blip into a total outage.
 *     Move to a shared store if replica count ever climbs.
 */
import { ThrottlerModuleOptions } from '@nestjs/throttler';

export const THROTTLE_READ = 'read';
export const THROTTLE_WRITE = 'write';

/**
 * `ttl` is milliseconds in @nestjs/throttler v6.
 *
 * The default tier is what an unnamed route gets. `read` and `write` are only
 * applied where a controller opts in with @Throttle, so they do not stack onto
 * every route by accident.
 */
export const throttlerConfig: ThrottlerModuleOptions = {
  throttlers: [
    {
      name: 'default',
      ttl: 60_000,
      limit: 120,
    },
  ],
};

/** Feed/profile reads: a real user pages and opens profiles quickly. */
export const READ_LIMIT = { default: { limit: 60, ttl: 60_000 } };

/** Search: heavier per call, and the most useful endpoint to a scraper. */
export const SEARCH_LIMIT = { default: { limit: 20, ttl: 60_000 } };

/**
 * Actions another member feels. Interest spam and mass-shortlisting are the
 * abuse this exists to stop, so this is intentionally lower than anything a
 * frustrated real user would reach by tapping quickly.
 */
export const WRITE_LIMIT = { default: { limit: 20, ttl: 60_000 } };

/** Uploads: bandwidth and S3 cost per call. */
export const UPLOAD_LIMIT = { default: { limit: 10, ttl: 60_000 } };
