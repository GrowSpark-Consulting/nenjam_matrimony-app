import { createHmac } from 'crypto';
import {
  decideRefreshToken,
  generateRefreshToken,
  hashRefreshToken,
  RefreshTokenInput,
} from './refresh-token';

const NOW = new Date('2026-10-27T10:00:00.000Z');
const LATER = new Date('2026-11-26T10:00:00.000Z');

const input = (
  overrides: Partial<RefreshTokenInput> = {},
): RefreshTokenInput => ({
  found: true,
  revokedAt: null,
  expiresAt: LATER,
  now: NOW,
  agentStatus: 'ACTIVE',
  ...overrides,
});

describe('generateRefreshToken', () => {
  it('is 43 base64url characters (32 bytes) from the default source', () => {
    for (let i = 0; i < 200; i++) {
      const token = generateRefreshToken();
      expect(token).toHaveLength(43);
      expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    }
  });

  it('is different every time from the default source', () => {
    const tokens = new Set(
      Array.from({ length: 500 }, () => generateRefreshToken()),
    );
    expect(tokens.size).toBe(500);
  });

  it('asks the injected source for exactly 32 bytes', () => {
    const source = jest.fn((n: number) => Buffer.alloc(n, 0));
    generateRefreshToken(source);
    expect(source).toHaveBeenCalledTimes(1);
    expect(source).toHaveBeenCalledWith(32);
  });

  it('is predictable with an injected source', () => {
    expect(generateRefreshToken((n) => Buffer.alloc(n, 0))).toBe(
      'A'.repeat(43),
    );
    expect(generateRefreshToken((n) => Buffer.alloc(n, 0xff))).toBe(
      // 256 one-bits: 42 full groups of 63 ("_"), then 1111 + 00 = 60 ("8").
      `${'_'.repeat(42)}8`,
    );
  });

  it('never contains +, / or = (URL safe, unpadded)', () => {
    const token = generateRefreshToken((n) => Buffer.alloc(n, 0xfb));
    expect(token).not.toMatch(/[+/=]/);
  });

  it.each([16, 31, 33, 0])(
    'rejects a source that returns %p bytes',
    (length) => {
      expect(() => generateRefreshToken(() => Buffer.alloc(length))).toThrow(
        RangeError,
      );
    },
  );
});

describe('hashRefreshToken', () => {
  it('is HMAC-SHA256 hex keyed with the pepper', () => {
    const expected = createHmac('sha256', 'pepper-1')
      .update('token-abc')
      .digest('hex');
    expect(hashRefreshToken('token-abc', 'pepper-1')).toBe(expected);
  });

  it('is 64 lower-case hex characters', () => {
    expect(hashRefreshToken('token-abc', 'pepper-1')).toMatch(/^[0-9a-f]{64}$/);
  });

  it('is deterministic', () => {
    expect(hashRefreshToken('token-abc', 'pepper-1')).toBe(
      hashRefreshToken('token-abc', 'pepper-1'),
    );
  });

  it('differs with a different pepper', () => {
    expect(hashRefreshToken('token-abc', 'pepper-1')).not.toBe(
      hashRefreshToken('token-abc', 'pepper-2'),
    );
  });

  it('differs with a different token', () => {
    expect(hashRefreshToken('token-abc', 'pepper-1')).not.toBe(
      hashRefreshToken('token-abd', 'pepper-1'),
    );
  });

  it('does not contain the token', () => {
    const token = generateRefreshToken();
    expect(hashRefreshToken(token, 'pepper-1')).not.toContain(token);
  });

  it.each([
    ['an empty token', '', 'pepper'],
    ['an empty pepper', 'token', ''],
  ])('rejects %s', (_label, token, pepper) => {
    expect(() => hashRefreshToken(token, pepper)).toThrow(RangeError);
  });

  it('rejects non-string input', () => {
    expect(() =>
      hashRefreshToken(undefined as unknown as string, 'pepper'),
    ).toThrow(RangeError);
    expect(() => hashRefreshToken('token', null as unknown as string)).toThrow(
      RangeError,
    );
  });
});

describe('decideRefreshToken', () => {
  it('accepts a live token for an active agent', () => {
    expect(decideRefreshToken(input())).toEqual({ ok: true });
  });

  it('NOT_FOUND', () => {
    expect(decideRefreshToken(input({ found: false }))).toEqual({
      ok: false,
      reason: 'NOT_FOUND',
    });
  });

  it('REUSED_REVOKED_TOKEN', () => {
    expect(
      decideRefreshToken(
        input({ revokedAt: new Date('2026-10-26T00:00:00Z') }),
      ),
    ).toEqual({ ok: false, reason: 'REUSED_REVOKED_TOKEN' });
  });

  describe('EXPIRED', () => {
    it('is expired exactly at expiresAt', () => {
      expect(decideRefreshToken(input({ expiresAt: NOW }))).toEqual({
        ok: false,
        reason: 'EXPIRED',
      });
    });

    it('is still valid one millisecond before', () => {
      expect(
        decideRefreshToken(input({ expiresAt: new Date(NOW.getTime() + 1) })),
      ).toEqual({ ok: true });
    });

    it('is expired after expiresAt', () => {
      expect(
        decideRefreshToken(input({ expiresAt: new Date(NOW.getTime() - 1) })),
      ).toEqual({ ok: false, reason: 'EXPIRED' });
    });
  });

  describe('agent status (follows the API contract)', () => {
    it.each([
      'PENDING_APPROVAL',
      'ACTIVE',
      'REJECTED',
      'SUSPENDED',
      'TERMINATED',
    ])('%s may refresh', (agentStatus) => {
      expect(decideRefreshToken(input({ agentStatus }))).toEqual({ ok: true });
    });

    it.each(['', 'active', 'DELETED', 'toString', '__proto__'])(
      'unknown status %p is AGENT_NOT_ALLOWED',
      (agentStatus) => {
        expect(decideRefreshToken(input({ agentStatus }))).toEqual({
          ok: false,
          reason: 'AGENT_NOT_ALLOWED',
        });
      },
    );
  });

  describe('order of checks', () => {
    const revoked = new Date('2026-10-26T00:00:00Z');
    const expired = new Date('2026-10-01T00:00:00Z');

    it('NOT_FOUND beats everything', () => {
      expect(
        decideRefreshToken(
          input({
            found: false,
            revokedAt: revoked,
            expiresAt: expired,
            agentStatus: 'DELETED',
          }),
        ),
      ).toEqual({ ok: false, reason: 'NOT_FOUND' });
    });

    it('REUSED_REVOKED_TOKEN beats EXPIRED and AGENT_NOT_ALLOWED', () => {
      expect(
        decideRefreshToken(
          input({
            revokedAt: revoked,
            expiresAt: expired,
            agentStatus: 'DELETED',
          }),
        ),
      ).toEqual({ ok: false, reason: 'REUSED_REVOKED_TOKEN' });
    });

    it('EXPIRED beats AGENT_NOT_ALLOWED', () => {
      expect(
        decideRefreshToken(
          input({ expiresAt: expired, agentStatus: 'DELETED' }),
        ),
      ).toEqual({ ok: false, reason: 'EXPIRED' });
    });
  });

  describe('date validation', () => {
    const bad = new Date('nope');

    it('rejects an invalid now, even when the row was not found', () => {
      expect(() =>
        decideRefreshToken(input({ found: false, now: bad })),
      ).toThrow(RangeError);
    });

    it('rejects an invalid expiresAt', () => {
      expect(() => decideRefreshToken(input({ expiresAt: bad }))).toThrow(
        RangeError,
      );
    });

    it('rejects an invalid revokedAt', () => {
      expect(() => decideRefreshToken(input({ revokedAt: bad }))).toThrow(
        RangeError,
      );
    });

    it('does not check the row dates when the row was not found', () => {
      expect(
        decideRefreshToken(
          input({ found: false, expiresAt: bad, revokedAt: bad }),
        ),
      ).toEqual({ ok: false, reason: 'NOT_FOUND' });
    });
  });
});
