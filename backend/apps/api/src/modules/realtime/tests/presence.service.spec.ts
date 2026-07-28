import { PresenceService, STALE_AFTER_MS } from '../presence.service';

/**
 * A tiny in-memory stand-in for the subset of ioredis commands PresenceService
 * uses, with faithful semantics (sorted-set scores, range removal, string
 * get/set). It lets the Redis branch be tested without a real Redis — the
 * in-memory *fallback* branch is covered separately by the live socket test.
 */
class FakeRedis {
  status = 'ready';
  private zsets = new Map<string, Map<string, number>>();
  private strings = new Map<string, string>();

  private set_(key: string): Map<string, number> {
    let s = this.zsets.get(key);
    if (!s) this.zsets.set(key, (s = new Map<string, number>()));
    return s;
  }

  zadd(key: string, score: number, member: string): Promise<number> {
    const existed = this.set_(key).has(member);
    this.set_(key).set(member, score);
    return Promise.resolve(existed ? 0 : 1);
  }

  zremrangebyscore(key: string, min: number, max: number): Promise<number> {
    const s = this.zsets.get(key);
    if (!s) return Promise.resolve(0);
    let removed = 0;
    for (const [m, score] of s) {
      if (score >= min && score <= max) {
        s.delete(m);
        removed++;
      }
    }
    return Promise.resolve(removed);
  }

  zrem(key: string, member: string): Promise<number> {
    const s = this.zsets.get(key);
    if (!s) return Promise.resolve(0);
    return Promise.resolve(s.delete(member) ? 1 : 0);
  }

  zcard(key: string): Promise<number> {
    return Promise.resolve(this.zsets.get(key)?.size ?? 0);
  }

  pexpire(): Promise<number> {
    return Promise.resolve(1);
  }

  get(key: string): Promise<string | null> {
    return Promise.resolve(this.strings.get(key) ?? null);
  }

  set(key: string, value: string): Promise<'OK'> {
    this.strings.set(key, value);
    return Promise.resolve('OK');
  }

  multi(): FakeMulti {
    return new FakeMulti(this);
  }
}

/** Minimal chainable MULTI that just runs each queued op in order on exec(). */
class FakeMulti {
  private ops: Array<() => Promise<unknown>> = [];
  constructor(private readonly redis: FakeRedis) {}
  zadd(key: string, score: number, member: string): this {
    this.ops.push(() => this.redis.zadd(key, score, member));
    return this;
  }
  zremrangebyscore(key: string, min: number, max: number): this {
    this.ops.push(() => this.redis.zremrangebyscore(key, min, max));
    return this;
  }
  pexpire(): this {
    this.ops.push(() => this.redis.pexpire());
    return this;
  }
  async exec(): Promise<unknown[]> {
    const out: unknown[] = [];
    for (const op of this.ops) out.push(await op());
    return out;
  }
}

function build() {
  const redis = new FakeRedis();
  const service = new PresenceService({ getClient: () => redis } as never);
  return { service, redis };
}

describe('PresenceService (Redis branch)', () => {
  afterEach(() => jest.restoreAllMocks());

  it('marks a user online after a device touch and offline once removed', async () => {
    const { service } = build();
    expect(await service.isOnline('u1')).toBe(false);
    await service.touch('u1', 'devA');
    expect(await service.isOnline('u1')).toBe(true);
    await service.remove('u1', 'devA');
    expect(await service.isOnline('u1')).toBe(false);
  });

  it('stays online while any of multiple devices remains', async () => {
    const { service } = build();
    await service.touch('u1', 'devA');
    await service.touch('u1', 'devB');
    await service.remove('u1', 'devA');
    expect(await service.isOnline('u1')).toBe(true); // devB still present
    await service.remove('u1', 'devB');
    expect(await service.isOnline('u1')).toBe(false);
  });

  it('ages out a device that stopped heartbeating (self-healing on read)', async () => {
    const { service } = build();
    const t0 = 1_000_000_000_000;
    jest.spyOn(Date, 'now').mockReturnValue(t0);
    await service.touch('u1', 'devA');
    expect(await service.isOnline('u1')).toBe(true);

    // Jump past the stale window with no new heartbeat — read prunes the device.
    jest.spyOn(Date, 'now').mockReturnValue(t0 + STALE_AFTER_MS + 1);
    expect(await service.isOnline('u1')).toBe(false);
  });

  it('records last-seen when the final device disconnects', async () => {
    const { service } = build();
    const t0 = 1_700_000_000_000;
    jest.spyOn(Date, 'now').mockReturnValue(t0);
    await service.touch('u1', 'devA');
    await service.remove('u1', 'devA');

    const info = await service.presenceOf('u1');
    expect(info.online).toBe(false);
    expect(info.lastSeenAt?.getTime()).toBe(t0);
  });

  it('reports online with a fresh lastSeenAt while connected', async () => {
    const { service } = build();
    await service.touch('u1', 'devA');
    const info = await service.presenceOf('u1');
    expect(info.online).toBe(true);
    expect(info.lastSeenAt).toBeInstanceOf(Date);
  });
});

describe('PresenceService (in-memory fallback branch)', () => {
  function buildDown() {
    const redis = { getClient: () => ({ status: 'connecting' }) };
    return new PresenceService(redis as never);
  }

  it('tracks presence and last-seen purely in memory when Redis is not ready', async () => {
    const service = buildDown();
    const t0 = 1_800_000_000_000;
    jest.spyOn(Date, 'now').mockReturnValue(t0);

    await service.touch('u1', 'devA');
    await service.touch('u1', 'devB');
    expect(await service.isOnline('u1')).toBe(true);

    await service.remove('u1', 'devA');
    expect(await service.isOnline('u1')).toBe(true);

    await service.remove('u1', 'devB');
    expect(await service.isOnline('u1')).toBe(false);
    const info = await service.presenceOf('u1');
    expect(info.lastSeenAt?.getTime()).toBe(t0);

    jest.restoreAllMocks();
  });

  it('ages out stale devices in memory too', async () => {
    const service = buildDown();
    const t0 = 1_810_000_000_000;
    jest.spyOn(Date, 'now').mockReturnValue(t0);
    await service.touch('u1', 'devA');
    expect(await service.isOnline('u1')).toBe(true);
    jest.spyOn(Date, 'now').mockReturnValue(t0 + STALE_AFTER_MS + 1);
    expect(await service.isOnline('u1')).toBe(false);
    jest.restoreAllMocks();
  });
});
