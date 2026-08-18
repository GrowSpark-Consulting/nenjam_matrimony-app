import {
  FeedContextService,
  feedContextKey,
  invalidateFeedContext,
  FEED_CONTEXT_CACHE_TTL_SECONDS,
} from '../cache/feed-context.cache';
import type { RedisService } from '@app/cache';
import type { FeedRepository } from '../repositories/feed.repository';
import type { PreferenceRepository } from '../repositories/preference.repository';

const SELF = {
  gender: 'MALE',
  caste: 'Iyer',
  currentCity: 'Chennai',
  currentState: 'Tamil Nadu',
  motherTongue: 'Tamil',
  userId: 'u1',
  dob: new Date('1996-05-01'),
  heightCm: 175,
  religion: 'Hindu',
  community: 'Brahmin',
  highestEducation: 'B.E',
  profession: 'Software Engineer',
  maritalStatus: 'NEVER_MARRIED',
  dietaryHabits: 'Vegetarian',
  smokingHabits: 'Never',
  drinkingHabits: 'Never',
  profileCompletePct: 90,
  updatedAt: new Date('2026-08-01'),
};

const PREF = { minAge: 25, maxAge: 32, preferredCastes: ['Iyer'] };

const settle = (): Promise<void> => new Promise((r) => setImmediate(r));

function build(clientOver: Record<string, unknown> = {}) {
  const store = new Map<string, string>();
  const client = {
    status: 'ready',
    get: jest.fn(async (k: string) => store.get(k) ?? null),
    set: jest.fn(async (k: string, v: string) => {
      store.set(k, v);
      return 'OK';
    }),
    del: jest.fn(async (k: string) => (store.delete(k) ? 1 : 0)),
    ...clientOver,
  };
  const redis = { getClient: () => client } as unknown as RedisService;
  const findSelf = jest.fn().mockResolvedValue(SELF);
  const findByUserId = jest.fn().mockResolvedValue(PREF);
  const svc = new FeedContextService(
    redis,
    { findSelf } as unknown as FeedRepository,
    { findByUserId } as unknown as PreferenceRepository,
  );
  return { svc, client, redis, findSelf, findByUserId, store };
}

describe('FeedContextService', () => {
  it('uses a stable, user-scoped key', () => {
    expect(feedContextKey('abc')).toBe('feed:context:abc');
  });

  describe('cache MISS', () => {
    it('reads both rows from the database and returns them', async () => {
      const { svc, findSelf, findByUserId } = build();
      const ctx = await svc.load('u1');
      expect(findSelf).toHaveBeenCalledWith('u1');
      expect(findByUserId).toHaveBeenCalledWith('u1');
      expect(ctx.self).toEqual(SELF);
      expect(ctx.pref).toEqual(PREF);
    });

    it('stores the context with the configured TTL', async () => {
      const { svc, client } = build();
      await svc.load('u1');
      await settle();
      expect(client.set).toHaveBeenCalledWith(
        'feed:context:u1',
        expect.any(String),
        'EX',
        FEED_CONTEXT_CACHE_TTL_SECONDS,
      );
    });

    it('does not cache a member who has no finalized profile', async () => {
      const store = new Map<string, string>();
      const client = {
        status: 'ready',
        get: jest.fn(async () => null),
        set: jest.fn(async () => 'OK'),
        del: jest.fn(async () => 1),
      };
      const svc = new FeedContextService(
        { getClient: () => client } as unknown as RedisService,
        { findSelf: jest.fn().mockResolvedValue(null) } as unknown as FeedRepository,
        { findByUserId: jest.fn().mockResolvedValue(null) } as unknown as PreferenceRepository,
      );
      await svc.load('u1');
      await settle();
      expect(client.set).not.toHaveBeenCalled();
      expect(store.size).toBe(0);
    });
  });

  describe('cache HIT', () => {
    it('serves from Redis without touching the database', async () => {
      const { svc, findSelf, findByUserId } = build();
      await svc.load('u1');
      await settle();
      findSelf.mockClear();
      findByUserId.mockClear();

      const ctx = await svc.load('u1');
      expect(findSelf).not.toHaveBeenCalled();
      expect(findByUserId).not.toHaveBeenCalled();
      expect(ctx.self?.userId).toBe('u1');
      expect(ctx.pref).toEqual(PREF);
    });

    it('restores Date fields that JSON turned into strings', async () => {
      const { svc } = build();
      await svc.load('u1');
      await settle();
      const ctx = await svc.load('u1');
      // Scoring does date arithmetic on these — a string would silently break
      // age and activity decay.
      expect(ctx.self?.dob).toBeInstanceOf(Date);
      expect(ctx.self?.updatedAt).toBeInstanceOf(Date);
      expect(ctx.self?.dob?.getTime()).toBe(SELF.dob.getTime());
    });
  });

  describe('Redis unavailable — must never break the feed', () => {
    it('falls back to the database when the client is not ready', async () => {
      const { svc, findSelf } = build({ status: 'connecting' });
      const ctx = await svc.load('u1');
      expect(findSelf).toHaveBeenCalled();
      expect(ctx.self).toEqual(SELF);
    });

    it('falls back when GET throws', async () => {
      const { svc, findSelf } = build({
        get: jest.fn().mockRejectedValue(new Error('connection lost')),
      });
      const ctx = await svc.load('u1');
      expect(findSelf).toHaveBeenCalled();
      expect(ctx.self).toEqual(SELF);
    });

    it('still returns data when SET throws', async () => {
      const { svc } = build({ set: jest.fn().mockRejectedValue(new Error('OOM')) });
      await expect(svc.load('u1')).resolves.toMatchObject({ self: SELF });
    });

    it('falls back when the cached payload is corrupt', async () => {
      const { svc, client, findSelf } = build();
      (client.get as jest.Mock).mockResolvedValueOnce('{not json');
      const ctx = await svc.load('u1');
      expect(findSelf).toHaveBeenCalled();
      expect(ctx.self).toEqual(SELF);
    });
  });

  describe('invalidation', () => {
    it('deletes the key for the right user', async () => {
      const { redis, client } = build();
      await invalidateFeedContext(redis, 'u1');
      expect(client.del).toHaveBeenCalledWith('feed:context:u1');
    });

    it('never throws when Redis is down', async () => {
      const { redis } = build({ del: jest.fn().mockRejectedValue(new Error('down')) });
      await expect(invalidateFeedContext(redis, 'u1')).resolves.toBeUndefined();
    });

    it('is a no-op when the client is not ready', async () => {
      const { redis, client } = build({ status: 'end' });
      await invalidateFeedContext(redis, 'u1');
      expect(client.del).not.toHaveBeenCalled();
    });

    it('prevents a stale read: after invalidation the next load hits the DB', async () => {
      const { svc, redis, findSelf, findByUserId } = build();
      await svc.load('u1');
      await settle();

      // Preferences change underneath the cache.
      const updated = { ...PREF, minAge: 40 };
      findByUserId.mockResolvedValue(updated);

      // Without invalidation the stale copy is still served...
      const stale = await svc.load('u1');
      expect(stale.pref).toEqual(PREF);

      // ...and after invalidation the next read is authoritative.
      await invalidateFeedContext(redis, 'u1');
      findSelf.mockClear();
      const fresh = await svc.load('u1');
      expect(findSelf).toHaveBeenCalled();
      expect(fresh.pref).toEqual(updated);
    });

    it('only touches the invalidated user, never another member', async () => {
      const { svc, redis, store } = build();
      await svc.load('u1');
      await svc.load('u2');
      await settle();
      expect(store.has('feed:context:u1')).toBe(true);
      expect(store.has('feed:context:u2')).toBe(true);

      await invalidateFeedContext(redis, 'u1');
      expect(store.has('feed:context:u1')).toBe(false);
      expect(store.has('feed:context:u2')).toBe(true);
    });
  });

  describe('what is NOT cached', () => {
    it('stores no safety-critical or secret fields', async () => {
      const { svc, store } = build();
      await svc.load('u1');
      await settle();
      const payload = store.get('feed:context:u1') ?? '';
      // Blocks, account status and deletedAt must stay live in buildFeedWhere;
      // credentials must never be in Redis at all.
      for (const forbidden of [
        'deletedAt',
        'status',
        'blocked',
        'firebaseUid',
        'token',
        'password',
        'email',
        'phone',
      ]) {
        expect(payload).not.toContain(forbidden);
      }
    });
  });
});
