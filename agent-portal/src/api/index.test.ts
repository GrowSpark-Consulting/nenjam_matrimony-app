import { resolveApiConfig } from '.';

describe('resolveApiConfig (no implicit mock fallback)', () => {
  const PROD = { DEV: false };
  const DEV = { DEV: true };

  it('production with the real API URL → live', () => {
    expect(
      resolveApiConfig({ ...PROD, VITE_API_BASE_URL: 'https://nenjam-matrimony.onrender.com/' }),
    ).toEqual({ mode: 'live', baseUrl: 'https://nenjam-matrimony.onrender.com' });
  });

  it('production NEVER falls back to mocks: a missing URL is an error', () => {
    expect(resolveApiConfig({ ...PROD })).toEqual({
      mode: 'invalid',
      reason: 'VITE_API_BASE_URL is not set.',
    });
    expect(resolveApiConfig({ ...PROD, VITE_API_BASE_URL: '   ' }).mode).toBe('invalid');
  });

  it('production refuses mocks even when asked for', () => {
    expect(
      resolveApiConfig({
        ...PROD,
        VITE_USE_MOCKS: 'true',
        VITE_API_BASE_URL: 'https://nenjam-matrimony.onrender.com',
      }),
    ).toEqual({ mode: 'invalid', reason: 'Mock data cannot be used in a production build.' });
  });

  it('mocks only when explicitly chosen in development', () => {
    expect(resolveApiConfig({ ...DEV, VITE_USE_MOCKS: 'true' })).toEqual({ mode: 'mock' });
    expect(resolveApiConfig({ ...DEV }).mode).toBe('invalid');
  });

  it('rejects invalid, insecure or decorated URLs', () => {
    for (const url of [
      'not a url',
      'http://nenjam-matrimony.onrender.com',
      'ftp://x.example',
      'https://api.example?debug=1',
      'https://user:pw@api.example',
    ]) {
      expect(resolveApiConfig({ ...PROD, VITE_API_BASE_URL: url }).mode, url).toBe('invalid');
    }
  });

  it('http is allowed only to localhost, and only in development', () => {
    expect(resolveApiConfig({ ...DEV, VITE_API_BASE_URL: 'http://127.0.0.1:3000' })).toEqual({
      mode: 'live',
      baseUrl: 'http://127.0.0.1:3000',
    });
    expect(resolveApiConfig({ ...PROD, VITE_API_BASE_URL: 'http://localhost:3000' }).mode).toBe(
      'invalid',
    );
    expect(resolveApiConfig({ ...DEV, VITE_API_BASE_URL: 'http://10.0.0.5:3000' }).mode).toBe(
      'invalid',
    );
  });
});
