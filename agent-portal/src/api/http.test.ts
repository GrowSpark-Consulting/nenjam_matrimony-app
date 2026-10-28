import { ApiError } from './errors';
import { HttpClient } from './http';
import { SessionStore } from './session';
import type { AgentSession } from './types';

function memoryStorage(): Storage {
  const m = new Map<string, string>();
  return {
    getItem: (k) => m.get(k) ?? null,
    setItem: (k, v) => void m.set(k, v),
    removeItem: (k) => void m.delete(k),
    clear: () => m.clear(),
    key: (i) => [...m.keys()][i] ?? null,
    get length() {
      return m.size;
    },
  };
}

const agentSession = (n: number): AgentSession => ({
  scope: 'AGENT',
  accessToken: `access-${n}`,
  refreshToken: `refresh-${n}`,
  expiresInSeconds: 900,
  agent: {} as AgentSession['agent'],
});

const json = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers });

type FetchArgs = [string, RequestInit];

describe('HttpClient', () => {
  let sessions: SessionStore;
  beforeEach(() => {
    sessions = new SessionStore(memoryStorage());
  });

  it('sends Accept-Version: 1 on every call, plus the agent bearer token', async () => {
    sessions.set(agentSession(1));
    const fetchFn = vi.fn(async (..._args: FetchArgs) => json(200, { ok: true }));
    const http = new HttpClient('https://api.test/', sessions, fetchFn as unknown as typeof fetch);
    await http.request('GET', '/agent/me');
    await http.request('POST', '/agent/auth/otp/request', {
      auth: false,
      body: { phone: '+919000000005' },
    });
    const [first, second] = fetchFn.mock.calls;
    expect(first[0]).toBe('https://api.test/agent/me');
    expect(first[1].headers).toMatchObject({
      'Accept-Version': '1',
      Authorization: 'Bearer access-1',
    });
    expect(second[1].headers).toMatchObject({ 'Accept-Version': '1' });
    expect(second[1].headers).not.toHaveProperty('Authorization');
  });

  it('refreshes ONCE for concurrent TOKEN_EXPIRED calls, stores the new pair, retries', async () => {
    sessions.set(agentSession(1));
    let refreshes = 0;
    const fetchFn = vi.fn(async (url: string, init: RequestInit) => {
      const auth = (init.headers as Record<string, string>).Authorization;
      if (url.endsWith('/agent/auth/refresh')) {
        refreshes++;
        expect(JSON.parse(init.body as string)).toEqual({ refreshToken: 'refresh-1' });
        return json(200, agentSession(2));
      }
      if (auth === 'Bearer access-1') {
        return json(401, { message: 'expired', code: 'TOKEN_EXPIRED' });
      }
      return json(200, { ok: auth });
    });
    const http = new HttpClient('https://api.test', sessions, fetchFn as unknown as typeof fetch);
    const results = await Promise.all([
      http.request<{ ok: string }>('GET', '/agent/balance'),
      http.request<{ ok: string }>('GET', '/agent/me'),
    ]);
    expect(refreshes).toBe(1);
    expect(results.map((r) => r.ok)).toEqual(['Bearer access-2', 'Bearer access-2']);
    expect((sessions.get()!.session as AgentSession).refreshToken).toBe('refresh-2');
  });

  it('a reused refresh token ends the session', async () => {
    sessions.set(agentSession(1));
    const fetchFn = vi.fn(async (url: string) =>
      url.endsWith('/refresh')
        ? json(401, { message: 'reused', code: 'REFRESH_TOKEN_REUSED' })
        : json(401, { message: 'expired', code: 'TOKEN_EXPIRED' }),
    );
    const http = new HttpClient('https://api.test', sessions, fetchFn as unknown as typeof fetch);
    await expect(http.request('GET', '/agent/me')).rejects.toMatchObject({
      code: 'REFRESH_TOKEN_REUSED',
    });
    expect(sessions.get()).toBeNull();
  });

  it('an applicant session is never refreshed', async () => {
    sessions.set({ scope: 'APPLICANT', accessToken: 'app', expiresInSeconds: 900 });
    const fetchFn = vi.fn(async () => json(401, { message: 'expired', code: 'TOKEN_EXPIRED' }));
    const http = new HttpClient('https://api.test', sessions, fetchFn as unknown as typeof fetch);
    await expect(
      http.request('POST', '/agent/application', { body: {} }),
    ).rejects.toBeInstanceOf(ApiError);
    expect(fetchFn).toHaveBeenCalledTimes(1);
    expect(sessions.get()).toBeNull();
  });

  it('keeps code, message and Retry-After from errors; joins validation lists', async () => {
    const fetchFn = vi
      .fn()
      .mockResolvedValueOnce(
        json(429, { message: 'slow down', code: 'RATE_LIMITED' }, { 'Retry-After': '30' }),
      )
      .mockResolvedValueOnce(
        json(400, { message: ['name too short', 'city required'], code: 'VALIDATION_FAILED' }),
      )
      .mockResolvedValueOnce(json(409, { message: 'Already applied.', code: 'SOME_FUTURE_CODE' }));
    const http = new HttpClient('https://api.test', sessions, fetchFn as unknown as typeof fetch);
    await expect(http.request('GET', '/x', { auth: false })).rejects.toMatchObject({
      status: 429,
      retryAfterSeconds: 30,
      isRateLimited: true,
    });
    await expect(http.request('GET', '/x', { auth: false })).rejects.toMatchObject({
      message: 'name too short, city required',
    });
    // An unconfirmed code is kept verbatim, never mapped to a guess.
    await expect(http.request('GET', '/x', { auth: false })).rejects.toMatchObject({
      status: 409,
      code: 'SOME_FUTURE_CODE',
      message: 'Already applied.',
    });
  });
});

/** A Web Locks stand-in shared by "tabs": callbacks run strictly one at a time. */
function sharedLock() {
  let tail: Promise<unknown> = Promise.resolve();
  return {
    request<T>(_name: string, cb: () => Promise<T>): Promise<T> {
      const run = tail.then(cb, cb);
      tail = run.catch(() => undefined);
      return run;
    },
  };
}

describe('HttpClient across tabs', () => {
  it('two tabs with an expired token make ONE refresh; the second reuses its result', async () => {
    const storage = memoryStorage();
    const tabA = new SessionStore(storage, Date.now, null);
    const tabB = new SessionStore(storage, Date.now, null);
    tabA.set(agentSession(1));
    let refreshes = 0;
    const fetchFn = vi.fn(async (url: string, init: RequestInit) => {
      const auth = (init.headers as Record<string, string>).Authorization;
      if (url.endsWith('/agent/auth/refresh')) {
        refreshes++;
        // Presenting refresh-1 twice would be reuse on the server.
        expect(JSON.parse(init.body as string)).toEqual({ refreshToken: 'refresh-1' });
        return json(200, agentSession(2));
      }
      return auth === 'Bearer access-1'
        ? json(401, { message: 'expired', code: 'TOKEN_EXPIRED' })
        : json(200, { ok: auth });
    });
    const lock = sharedLock();
    const a = new HttpClient('https://api.test', tabA, fetchFn as unknown as typeof fetch, lock);
    const b = new HttpClient('https://api.test', tabB, fetchFn as unknown as typeof fetch, lock);
    const [ra, rb] = await Promise.all([
      a.request<{ ok: string }>('GET', '/agent/me'),
      b.request<{ ok: string }>('GET', '/agent/balance'),
    ]);
    expect(refreshes).toBe(1);
    expect([ra.ok, rb.ok]).toEqual(['Bearer access-2', 'Bearer access-2']);
  });

  it('when the lock holder fails to refresh, the waiting tab signs out without a second refresh', async () => {
    const storage = memoryStorage();
    const tabA = new SessionStore(storage, Date.now, null);
    const tabB = new SessionStore(storage, Date.now, null);
    tabA.set(agentSession(1));
    let refreshes = 0;
    const fetchFn = vi.fn(async (url: string) => {
      if (url.endsWith('/agent/auth/refresh')) {
        refreshes++;
        return json(401, { message: 'expired', code: 'REFRESH_TOKEN_EXPIRED' });
      }
      return json(401, { message: 'expired', code: 'TOKEN_EXPIRED' });
    });
    const lock = sharedLock();
    const a = new HttpClient('https://api.test', tabA, fetchFn as unknown as typeof fetch, lock);
    const b = new HttpClient('https://api.test', tabB, fetchFn as unknown as typeof fetch, lock);
    const results = await Promise.allSettled([
      a.request('GET', '/agent/me'),
      b.request('GET', '/agent/balance'),
    ]);
    expect(results.map((r) => r.status)).toEqual(['rejected', 'rejected']);
    // Only the lock holder ever presented the refresh token: no reuse.
    expect(refreshes).toBe(1);
    expect(tabA.get()).toBeNull();
    expect(tabB.get()).toBeNull();
  });

  it('a network failure is a calm ApiError, and the session is kept', async () => {
    const sessions = new SessionStore(memoryStorage(), Date.now, null);
    sessions.set(agentSession(1));
    const fetchFn = vi.fn(async () => {
      throw new TypeError('Failed to fetch');
    });
    const http = new HttpClient('https://api.test', sessions, fetchFn as unknown as typeof fetch, null);
    await expect(http.request('GET', '/agent/me')).rejects.toMatchObject({
      status: 0,
      isNetworkError: true,
    });
    expect(sessions.get()).not.toBeNull();
  });

  it('never sends cookies or a referrer; the token goes in the header only', async () => {
    const sessions = new SessionStore(memoryStorage(), Date.now, null);
    sessions.set(agentSession(1));
    const fetchFn = vi.fn(async (..._args: FetchArgs) => json(200, {}));
    const http = new HttpClient('https://api.test', sessions, fetchFn as unknown as typeof fetch, null);
    await http.request('GET', '/agent/referrals', { query: { limit: 20, cursor: 'abc' } });
    const [url, init] = fetchFn.mock.calls[0];
    expect(url).toBe('https://api.test/agent/referrals?limit=20&cursor=abc');
    expect(url).not.toContain('access-1');
    expect(init).toMatchObject({ credentials: 'omit', referrerPolicy: 'no-referrer' });
  });

  it('a 5xx keeps its status so the UI shows a generic sentence', async () => {
    const sessions = new SessionStore(memoryStorage(), Date.now, null);
    const fetchFn = vi.fn(async () => json(500, { message: 'TypeError at foo.ts:12' }));
    const http = new HttpClient('https://api.test', sessions, fetchFn as unknown as typeof fetch, null);
    await expect(http.request('GET', '/x', { auth: false })).rejects.toMatchObject({
      isServerError: true,
    });
  });
});

describe('SessionStore across tabs', () => {
  it('a storage event from another tab reaches subscribers (e.g. sign-out)', () => {
    const storage = memoryStorage();
    const listeners: ((e: StorageEvent) => void)[] = [];
    const events = {
      addEventListener: (_t: string, l: (e: StorageEvent) => void) => listeners.push(l),
    } as unknown as Pick<Window, 'addEventListener'>;
    const store = new SessionStore(storage, Date.now, events);
    store.set(agentSession(1));
    const seen: unknown[] = [];
    store.subscribe((s) => seen.push(s));
    storage.removeItem('nenjam.agentPortal.session'); // the other tab signed out
    listeners[0]({ key: 'nenjam.agentPortal.session' } as StorageEvent);
    expect(seen).toEqual([null]);
  });
});
