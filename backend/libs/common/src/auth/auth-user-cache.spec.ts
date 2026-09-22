import type { RedisService } from '@app/cache';
import {
  BLOCKED_ACCOUNT_STATUSES,
  getCachedAuthUser,
  getCachedUserId,
  isAccountUsable,
  setCachedAuthUser,
} from './auth-user-cache';

/**
 * The cached account carries the status, so the auth guard can refuse a
 * suspended caller without paying the DB round trip this cache exists to
 * remove. Fail-open throughout: a Redis problem must never lock anyone out,
 * and must never let a blocked account in either.
 */
function redis(over: Partial<Record<string, unknown>> = {}): {
  service: RedisService;
  store: Map<string, string>;
} {
  const store = new Map<string, string>();
  const client = {
    status: 'ready',
    get: (key: string) => Promise.resolve(store.get(key) ?? null),
    set: (key: string, value: string) => {
      store.set(key, value);
      return Promise.resolve('OK');
    },
    del: (key: string) => {
      store.delete(key);
      return Promise.resolve(1);
    },
    ...over,
  };
  return {
    service: { getClient: () => client } as unknown as RedisService,
    store,
  };
}

const ACTIVE = { id: 'u1', status: 'PENDING_VERIFICATION', deleted: false };

describe('auth user cache', () => {
  it('round-trips the account, status included', async () => {
    const { service } = redis();
    await setCachedAuthUser(service, 'uid-1', ACTIVE);
    await expect(getCachedAuthUser(service, 'uid-1')).resolves.toEqual(ACTIVE);
  });

  it('withholds the id of an account that may not use the API', async () => {
    for (const status of BLOCKED_ACCOUNT_STATUSES) {
      const { service } = redis();
      await setCachedAuthUser(service, 'uid-1', {
        id: 'u1',
        status,
        deleted: false,
      });
      // The record is still readable — the guard needs it to explain itself —
      // but the id-only accessor refuses to hand back a blocked account.
      await expect(getCachedAuthUser(service, 'uid-1')).resolves.toMatchObject({
        status,
      });
      await expect(getCachedUserId(service, 'uid-1')).resolves.toBeNull();
    }
  });

  it('withholds the id of a soft-deleted account', async () => {
    const { service } = redis();
    await setCachedAuthUser(service, 'uid-1', { ...ACTIVE, deleted: true });
    await expect(getCachedUserId(service, 'uid-1')).resolves.toBeNull();
  });

  it('returns the id for a usable account', async () => {
    const { service } = redis();
    await setCachedAuthUser(service, 'uid-1', ACTIVE);
    await expect(getCachedUserId(service, 'uid-1')).resolves.toBe('u1');
  });

  it('treats a v1 entry (a bare id string) as a miss rather than trusting it', async () => {
    // Left over from a previous deploy: no status, so it cannot be judged.
    const { service, store } = redis();
    store.set('authuser:v2:uid:uid-1', 'u1');
    await expect(getCachedAuthUser(service, 'uid-1')).resolves.toBeNull();
    await expect(getCachedUserId(service, 'uid-1')).resolves.toBeNull();
  });

  it('treats unreadable JSON and a missing status as a miss', async () => {
    const { service, store } = redis();
    store.set('authuser:v2:uid:uid-1', '{not json');
    await expect(getCachedAuthUser(service, 'uid-1')).resolves.toBeNull();
    store.set('authuser:v2:uid:uid-1', JSON.stringify({ id: 'u1' }));
    await expect(getCachedAuthUser(service, 'uid-1')).resolves.toBeNull();
  });

  it('is a no-op when Redis is down, never an error', async () => {
    const down = {
      getClient: () => ({ status: 'connecting' }),
    } as unknown as RedisService;
    await expect(
      setCachedAuthUser(down, 'uid-1', ACTIVE),
    ).resolves.toBeUndefined();
    await expect(getCachedAuthUser(down, 'uid-1')).resolves.toBeNull();
    await expect(getCachedUserId(down, 'uid-1')).resolves.toBeNull();
  });

  it('swallows a throwing Redis client', async () => {
    const { service } = redis({
      get: () => Promise.reject(new Error('boom')),
      set: () => Promise.reject(new Error('boom')),
    });
    await expect(getCachedAuthUser(service, 'uid-1')).resolves.toBeNull();
    await expect(
      setCachedAuthUser(service, 'uid-1', ACTIVE),
    ).resolves.toBeUndefined();
  });

  describe('isAccountUsable', () => {
    it('blocks suspended, banned, deactivated and deleted accounts', () => {
      for (const status of BLOCKED_ACCOUNT_STATUSES) {
        expect(isAccountUsable({ status, deleted: false })).toBe(false);
      }
      expect(isAccountUsable({ status: 'ACTIVE', deleted: true })).toBe(false);
    });

    it('admits every state a real member is actually in', () => {
      // A denylist on purpose: nothing in this app promotes an account out of
      // PENDING_VERIFICATION, so requiring ACTIVE would lock out everyone.
      expect(
        isAccountUsable({ status: 'PENDING_VERIFICATION', deleted: false }),
      ).toBe(true);
      expect(isAccountUsable({ status: 'ACTIVE', deleted: false })).toBe(true);
      expect(isAccountUsable({ status: '', deleted: false })).toBe(true);
    });
  });
});
