import type { RedisService } from '@app/cache';

/**
 * Caches the Firebase-UID → internal account record that the FirebaseAuthGuard
 * resolves on EVERY authenticated request.
 *
 * Why this exists: against a managed Postgres in another region (Neon
 * us-east-1) a single round trip costs ~250-300ms, and the guard's
 * `user.findUnique({ where: { firebaseUid } })` runs once per request — it was
 * the one unavoidable DB hop on the hot path of the entire API. The mapping
 * only changes when an account is created, deleted, or its Firebase UID is
 * rotated/re-linked, so a short-TTL cache removes that hop from virtually every
 * request while staying correct via explicit invalidation on deletion.
 *
 * The id is cached WITH the account's status, so the guard can refuse a
 * suspended/banned/deactivated caller without paying that round trip back. The
 * guard's other returned fields (uid, email, phone_number) come straight from
 * the verified token, never the DB.
 *
 * Staleness that matters: a status changed directly in the database keeps
 * working for up to the TTL below. Whatever suspends or bans an account should
 * therefore call [invalidateCachedUserId] so the change lands on the very next
 * request — account deletion does (see AccountDeletionService), and
 * `pnpm account:status` (scripts/set-account-status.ts) does it for moderation
 * actions taken by hand.
 *
 * The TTL is the backstop for the case that cannot call anything: a status
 * edited straight in SQL. It was 15 minutes, which meant a ban could take that
 * long to bite — far too long for the one control that stops an abusive member.
 * 60 seconds bounds it to something defensible while still removing the DB hop
 * from ~97% of requests: a member making a request every two seconds pays one
 * lookup per minute instead of thirty. The cost is one indexed primary-key
 * read per active member per minute, which at this scale is a rounding error
 * against the feed's own query load.
 *
 * Fail-open by design: Redis is a non-critical dependency (in dev it may not be
 * running at all — see RedisService.handleStartupFailure). Every call is a
 * no-op when the client isn't `ready` and swallows any Redis error, so auth
 * always falls back to the authoritative DB lookup. Caching must never be able
 * to lock a user out.
 */
export const AUTH_USER_CACHE_TTL_SECONDS = 60;

/**
 * `v2` because the value changed shape (a bare id string → JSON with the
 * status). A running deploy's `v1` entries are simply never read again and
 * expire on their own, which is cheaper and safer than parsing both forms.
 */
function cacheKey(firebaseUid: string): string {
  return `authuser:v2:uid:${firebaseUid}`;
}

/** The cached account: who they are, and whether they may still use the API. */
export interface CachedAuthUser {
  id: string;
  /** `User.status` as stored. */
  status: string;
  /** Whether the account is soft-deleted (`User.deletedAt` is set). */
  deleted: boolean;
}

/** Cached account for a Firebase UID, or null on miss / Redis down / bad JSON. */
export async function getCachedAuthUser(
  redis: RedisService,
  firebaseUid: string,
): Promise<CachedAuthUser | null> {
  const client = redis.getClient();
  if (client.status !== 'ready') return null;
  try {
    const raw = await client.get(cacheKey(firebaseUid));
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return null;
    const value = parsed as Partial<CachedAuthUser>;
    if (typeof value.id !== 'string' || typeof value.status !== 'string') {
      return null;
    }
    return {
      id: value.id,
      status: value.status,
      deleted: value.deleted === true,
    };
  } catch {
    // A miss, a Redis error and an unreadable payload are the same thing to the
    // caller: fall through to the authoritative DB read.
    return null;
  }
}

/** Cached internal user id only, for callers that do their own eligibility
 *  checks. Returns null whenever the cached account may not use the API, so a
 *  suspended caller is never served from cache. */
export async function getCachedUserId(
  redis: RedisService,
  firebaseUid: string,
): Promise<string | null> {
  const cached = await getCachedAuthUser(redis, firebaseUid);
  if (!cached || !isAccountUsable(cached)) return null;
  return cached.id;
}

/** Best-effort populate; silently skipped when Redis is unavailable. */
export async function setCachedAuthUser(
  redis: RedisService,
  firebaseUid: string,
  user: CachedAuthUser,
): Promise<void> {
  const client = redis.getClient();
  if (client.status !== 'ready') return;
  try {
    await client.set(
      cacheKey(firebaseUid),
      JSON.stringify(user),
      'EX',
      AUTH_USER_CACHE_TTL_SECONDS,
    );
  } catch {
    // Non-fatal — the next request just re-reads from the DB.
  }
}

/** Invalidate on account deletion, suspension or ban so the change takes
 *  effect on the next request rather than after the TTL. */
export async function invalidateCachedUserId(
  redis: RedisService,
  firebaseUid: string,
): Promise<void> {
  const client = redis.getClient();
  if (client.status !== 'ready') return;
  try {
    await client.del(cacheKey(firebaseUid));
  } catch {
    // Non-fatal — the entry expires within AUTH_USER_CACHE_TTL_SECONDS anyway.
  }
}

/**
 * Account states that may not use the API at all.
 *
 * Deliberately a denylist, matching the feed's eligibility rules: nothing in
 * this app ever promotes an account out of PENDING_VERIFICATION, so requiring
 * ACTIVE here would lock out every real member.
 */
export const BLOCKED_ACCOUNT_STATUSES: readonly string[] = [
  'SUSPENDED',
  'BANNED',
  'DEACTIVATED',
];

/** Whether this account may make authenticated requests. */
export function isAccountUsable(account: {
  status: string;
  deleted: boolean;
}): boolean {
  return !account.deleted && !BLOCKED_ACCOUNT_STATUSES.includes(account.status);
}
