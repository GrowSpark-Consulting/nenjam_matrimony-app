import { describe, expect, it, vi } from 'vitest';
import { ApiClient, ApiError, buildUrl, errorMessage } from './api';

function respond(status: number, body?: unknown): Response {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function client(fetchImpl: typeof fetch, extra: Partial<ConstructorParameters<typeof ApiClient>[0]> = {}) {
  return new ApiClient({
    baseUrl: 'https://api.example.test',
    getIdToken: () => Promise.resolve('id-token'),
    getSessionToken: () => 'session-token',
    fetchImpl,
    ...extra,
  });
}

describe('ApiClient', () => {
  it('sends the Firebase token and the admin session, never cookies', async () => {
    const fetchImpl = vi.fn(() => Promise.resolve(respond(200, { ok: true })));
    await expect(client(fetchImpl).get('/admin/me')).resolves.toEqual({ ok: true });
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('https://api.example.test/admin/me');
    expect(init.headers).toMatchObject({
      Authorization: 'Bearer id-token',
      'X-Admin-Session': 'session-token',
    });
    expect(init.credentials).toBe('omit');
  });

  it('turns an error body into an ApiError with its code and message', async () => {
    const fetchImpl = vi.fn(() =>
      Promise.resolve(
        respond(403, {
          statusCode: 403,
          error: 'Forbidden',
          code: 'ADMIN_PERMISSION_DENIED',
          message: 'Not permitted: requires plan.publish.',
        }),
      ),
    );
    const error = await client(fetchImpl).post('/x').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({
      status: 403,
      code: 'ADMIN_PERMISSION_DENIED',
      message: 'Not permitted: requires plan.publish.',
    });
  });

  it('reports a lost admin session so the app can ask for a new code', async () => {
    const onSessionLost = vi.fn();
    const fetchImpl = vi.fn(() =>
      Promise.resolve(respond(401, { code: 'ADMIN_SESSION_INVALID', message: 'ended' })),
    );
    await expect(client(fetchImpl, { onSessionLost }).get('/admin/me')).rejects.toBeInstanceOf(
      ApiError,
    );
    expect(onSessionLost).toHaveBeenCalledTimes(1);
  });

  it('asks for a step-up and retries the request once when it is confirmed', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(respond(401, { code: 'ADMIN_STEP_UP_REQUIRED', message: 'fresh code' }))
      .mockResolvedValueOnce(respond(200, { roles: [] }));
    const onStepUpRequired = vi.fn(() => Promise.resolve(true));
    await expect(
      client(fetchImpl as unknown as typeof fetch, { onStepUpRequired }).get('/admin/roles'),
    ).resolves.toEqual({ roles: [] });
    expect(onStepUpRequired).toHaveBeenCalledTimes(1);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it('does not retry when the step-up is cancelled', async () => {
    const fetchImpl = vi.fn(() =>
      Promise.resolve(respond(401, { code: 'ADMIN_STEP_UP_REQUIRED', message: 'fresh code' })),
    );
    const error = await client(fetchImpl, {
      onStepUpRequired: () => Promise.resolve(false),
    })
      .get('/admin/roles')
      .catch((e: unknown) => e);
    expect((error as ApiError).needsStepUp).toBe(true);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it('reports an unreachable server as status 0', async () => {
    const fetchImpl = vi.fn(() => Promise.reject(new TypeError('Failed to fetch')));
    const error = await client(fetchImpl).get('/admin/me').catch((e: unknown) => e);
    expect(error).toMatchObject({ status: 0 });
  });

  it('returns undefined for 204', async () => {
    const fetchImpl = vi.fn(() => Promise.resolve(new Response(null, { status: 204 })));
    await expect(client(fetchImpl).post('/admin/auth/logout')).resolves.toBeUndefined();
  });
});

describe('helpers', () => {
  it('builds query strings, skipping empty values', () => {
    expect(buildUrl('https://a.test', '/admin/x', { q: 'a b', status: '', limit: 25, cursor: null })).toBe(
      'https://a.test/admin/x?q=a+b&limit=25',
    );
  });

  it('joins validation message lists and falls back by status', () => {
    expect(errorMessage(400, { message: ['days must not be greater than 30', 'reason is required'] })).toBe(
      'days must not be greater than 30 reason is required',
    );
    expect(errorMessage(429, {})).toMatch(/Too many/);
    expect(errorMessage(0, null)).toMatch(/reach the server/);
  });
});
