import type { RedisService } from '@app/cache';

/**
 * Caches the near-immutable Firebase-UID → internal-user-id mapping that the
 * FirebaseAuthGuard resolves on EVERY authenticated request.
 *
 * Why this exists: against a managed Postgres in another region (Neon
 * us-east-1) a single round trip costs ~250-300ms, and the guard's
 * `user.findUnique({ where: { firebaseUid } })` runs once per request — it was
 * the one unavoidable DB hop on the hot path of the entire API. The mapping
 * only changes when an account is created, deleted, or its Firebase UID is
 * rotated/re-linked, so a short-TTL cache removes that hop from virtually every
 * request while staying correct via explicit invalidation on deletion.
 *
 * Only `user.id` is cached — the guard's other returned fields (uid, email,
 * phone_number) come straight from the verified token, never the DB.
 *
 * Fail-open by design: Redis is a non-critical dependency (in dev it may not be
 * running at all — see RedisService.handleStartupFailure). Every call is a
 * no-op when the client isn't `ready` and swallows any Redis error, so auth
 * always falls back to the authoritative DB lookup. Caching must never be able
 * to lock a user out.
 */
const AUTH_USER_CACHE_TTL_SECONDS = 900; // 15 minutes

function cacheKey(firebaseUid: string): string {
  return `authuser:uid:${firebaseUid}`;
}

/** Cached internal user id for a Firebase UID, or null on miss / Redis down. */
export async function getCachedUserId(
  redis: RedisService,
  firebaseUid: string,
): Promise<string | null> {
  const client = redis.getClient();
  if (client.status !== 'ready') return null;
  try {
    return await client.get(cacheKey(firebaseUid));
  } catch {
    return null;
  }
}

/** Best-effort populate; silently skipped when Redis is unavailable. */
export async function setCachedUserId(
  redis: RedisService,
  firebaseUid: string,
  userId: string,
): Promise<void> {
  const client = redis.getClient();
  if (client.status !== 'ready') return;
  try {
    await client.set(
      cacheKey(firebaseUid),
      userId,
      'EX',
      AUTH_USER_CACHE_TTL_SECONDS,
    );
  } catch {
    // Non-fatal — the next request just re-reads from the DB.
  }
}

/** Invalidate on account deletion so a deleted UID can't resolve from cache. */
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
