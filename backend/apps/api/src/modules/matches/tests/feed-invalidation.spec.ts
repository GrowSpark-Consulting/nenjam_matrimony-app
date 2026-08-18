import { FeedVersionService, feedVersionKey } from '../cache/feed-version.cache';
import { FeedInvalidationService } from '../cache/feed-invalidation.service';
import { feedContextKey } from '../cache/feed-context.cache';
import { RealtimeEvents } from '../../realtime/realtime.events';
import type { RedisService } from '@app/cache';
import type { RealtimeGateway } from '../../realtime/realtime.gateway';

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
    incr: jest.fn(async (k: string) => {
      const next = Number(store.get(k) ?? '0') + 1;
      store.set(k, String(next));
      return next;
    }),
    ...clientOver,
  };
  const redis = { getClient: () => client } as unknown as RedisService;
  const version = new FeedVersionService(redis);
  const emitToUser = jest.fn();
  const realtime = { emitToUser } as unknown as RealtimeGateway;
  const svc = new FeedInvalidationService(redis, version, realtime);
  return { svc, version, client, store, emitToUser, redis };
}

describe('FeedVersionService', () => {
  it('uses a stable, user-scoped key', () => {
    expect(feedVersionKey('abc')).toBe('feed:version:abc');
  });

  it('starts at 0 for a member who has never been invalidated', async () => {
    const { version } = build();
    expect(await version.get('u1')).toBe(0);
  });

  it('increments monotonically', async () => {
    const { version } = build();
    expect(await version.bump('u1')).toBe(1);
    expect(await version.bump('u1')).toBe(2);
    expect(await version.get('u1')).toBe(2);
  });

  it('never hands two concurrent bumps the same number', async () => {
    const { version } = build();
    const results = await Promise.all(
      Array.from({ length: 25 }, () => version.bump('u1')),
    );
    // A client comparing versions would otherwise conclude nothing changed.
    expect(new Set(results).size).toBe(25);
  });

  it('returns a stable 0 when Redis is down, not a changing value', async () => {
    const { version } = build({ status: 'end' });
    expect(await version.get('u1')).toBe(0);
    expect(await version.get('u1')).toBe(0);
  });

  it('returns 0 rather than throwing when GET fails', async () => {
    const { version } = build({ get: jest.fn().mockRejectedValue(new Error('down')) });
    await expect(version.get('u1')).resolves.toBe(0);
  });

  it('returns 0 rather than throwing when INCR fails', async () => {
    const { version } = build({ incr: jest.fn().mockRejectedValue(new Error('down')) });
    await expect(version.bump('u1')).resolves.toBe(0);
  });
});

describe('FeedInvalidationService', () => {
  it('clears the context, bumps the version, and emits — in that order', async () => {
    const { svc, client, emitToUser } = build();
    const order: string[] = [];
    (client.del as jest.Mock).mockImplementation(async () => {
      order.push('del');
      return 1;
    });
    (client.incr as jest.Mock).mockImplementation(async () => {
      order.push('incr');
      return 7;
    });
    emitToUser.mockImplementation(() => order.push('emit'));

    await svc.invalidate('u1', 'profile_updated');

    // Clearing first matters: an eager client reacting to the event must not
    // be able to refetch and be served the cache it was just told to discard.
    expect(order).toEqual(['del', 'incr', 'emit']);
  });

  it('deletes the right context key', async () => {
    const { svc, client } = build();
    await svc.invalidate('u1', 'profile_updated');
    expect(client.del).toHaveBeenCalledWith(feedContextKey('u1'));
  });

  it('emits feed.invalidate with the new version and reason', async () => {
    const { svc, emitToUser } = build();
    await svc.invalidate('u1', 'preferences_updated');
    expect(emitToUser).toHaveBeenCalledWith(
      'u1',
      RealtimeEvents.feedInvalidate,
      expect.objectContaining({ version: 1, reason: 'preferences_updated' }),
    );
  });

  it('sends no profile data over the socket — only a signal', async () => {
    const { svc, emitToUser } = build();
    await svc.invalidate('u1', 'profile_updated');
    const payload = emitToUser.mock.calls[0][2] as Record<string, unknown>;
    expect(Object.keys(payload).sort()).toEqual(['at', 'reason', 'version']);
  });

  it('invalidates BOTH members when a block changes', async () => {
    const { svc, emitToUser, store } = build();
    await svc.invalidatePair('blocker', 'blocked', 'block_created');
    expect(emitToUser).toHaveBeenCalledTimes(2);
    expect(store.get(feedVersionKey('blocker'))).toBe('1');
    expect(store.get(feedVersionKey('blocked'))).toBe('1');
  });

  describe('never breaks the write it follows', () => {
    it('resolves when Redis is unavailable', async () => {
      const { svc } = build({ status: 'end' });
      await expect(svc.invalidate('u1', 'profile_updated')).resolves.toBeUndefined();
    });

    it('resolves when DEL throws', async () => {
      const { svc } = build({ del: jest.fn().mockRejectedValue(new Error('down')) });
      await expect(svc.invalidate('u1', 'profile_updated')).resolves.toBeUndefined();
    });

    it('resolves when the socket emit throws', async () => {
      const { svc } = build();
      const redis = { getClient: () => ({ status: 'ready', del: jest.fn(), incr: jest.fn(async () => 1) }) } as unknown as RedisService;
      const throwing = new FeedInvalidationService(
        redis,
        new FeedVersionService(redis),
        {
          emitToUser: () => {
            throw new Error('no socket server');
          },
        } as unknown as RealtimeGateway,
      );
      await expect(throwing.invalidate('u1', 'profile_updated')).resolves.toBeUndefined();
      void svc;
    });

    it('still emits for a member with no open socket', async () => {
      // emitToUser is a no-op when nobody is listening; that is the normal
      // case, not an error, so nothing here should special-case it.
      const { svc, emitToUser } = build();
      await svc.invalidate('offline-user', 'profile_updated');
      expect(emitToUser).toHaveBeenCalled();
    });
  });

  describe('staleness', () => {
    it('a client holding an old version can detect the change', async () => {
      const { svc, version } = build();
      const held = await version.get('u1');
      await svc.invalidate('u1', 'preferences_updated');
      const current = await version.get('u1');
      expect(current).toBeGreaterThan(held);
    });

    it('does not touch another member’s version', async () => {
      const { svc, version } = build();
      await svc.invalidate('u1', 'profile_updated');
      expect(await version.get('u2')).toBe(0);
    });
  });
});
