import {
  AgentAccessClaims,
  buildAgentAccessClaims,
  BuildAgentAccessClaimsInput,
  validateAgentAccessClaims,
} from './agent-access-claims';

// 2026-10-27T10:00:00.000Z = 1793095200 s
const NOW = new Date('2026-10-27T10:00:00.000Z');
const NOW_S = 1_793_095_200;
const ISS = 'nenjam-agent-api';
const AUD = 'nenjam-agent-app';

const buildInput = (
  overrides: Partial<BuildAgentAccessClaimsInput> = {},
): BuildAgentAccessClaimsInput => ({
  agentId: 'agent-1',
  phoneHash: 'hash-1',
  scope: 'AGENT',
  now: NOW,
  ttlSeconds: 900,
  issuer: ISS,
  audience: AUD,
  ...overrides,
});

const expected = (now: Date = NOW) => ({ issuer: ISS, audience: AUD, now });

const claims = (
  overrides: Partial<Record<keyof AgentAccessClaims, unknown>> = {},
): Record<string, unknown> => ({
  sub: 'agent-1',
  scope: 'AGENT',
  aud: AUD,
  iss: ISS,
  iat: NOW_S,
  exp: NOW_S + 900,
  ...overrides,
});

describe('buildAgentAccessClaims', () => {
  it('sanity: NOW is the epoch second used below', () => {
    expect(NOW.getTime() / 1000).toBe(NOW_S);
  });

  it('builds AGENT claims with the agent id as sub', () => {
    expect(buildAgentAccessClaims(buildInput())).toEqual({
      sub: 'agent-1',
      scope: 'AGENT',
      aud: AUD,
      iss: ISS,
      iat: NOW_S,
      exp: NOW_S + 900,
    });
  });

  it('builds APPLICANT claims with the phone hash as sub', () => {
    expect(
      buildAgentAccessClaims(buildInput({ scope: 'APPLICANT', agentId: null })),
    ).toEqual({
      sub: 'hash-1',
      scope: 'APPLICANT',
      aud: AUD,
      iss: ISS,
      iat: NOW_S,
      exp: NOW_S + 900,
    });
  });

  it('uses whole seconds, rounding iat down', () => {
    const result = buildAgentAccessClaims(
      buildInput({ now: new Date(NOW.getTime() + 999), ttlSeconds: 60 }),
    );
    expect(result.iat).toBe(NOW_S);
    expect(result.exp).toBe(NOW_S + 60);
    expect(Number.isInteger(result.iat)).toBe(true);
  });

  it('uses the ttl it is given', () => {
    expect(buildAgentAccessClaims(buildInput({ ttlSeconds: 1 })).exp).toBe(
      NOW_S + 1,
    );
  });

  it('round-trips through validateAgentAccessClaims', () => {
    for (const scope of ['AGENT', 'APPLICANT'] as const) {
      const built = buildAgentAccessClaims(
        buildInput({ scope, agentId: scope === 'AGENT' ? 'agent-1' : null }),
      );
      expect(validateAgentAccessClaims(built, expected())).toEqual({
        ok: true,
        claims: built,
      });
    }
  });

  describe('validation', () => {
    it.each([null, ''])(
      'an AGENT without an agentId (%p) throws',
      (agentId) => {
        expect(() => buildAgentAccessClaims(buildInput({ agentId }))).toThrow(
          RangeError,
        );
      },
    );

    it('an APPLICANT with an agentId throws', () => {
      expect(() =>
        buildAgentAccessClaims(buildInput({ scope: 'APPLICANT' })),
      ).toThrow(RangeError);
    });

    it('an APPLICANT without a phoneHash throws', () => {
      expect(() =>
        buildAgentAccessClaims(
          buildInput({ scope: 'APPLICANT', agentId: null, phoneHash: '' }),
        ),
      ).toThrow(RangeError);
    });

    it('an unknown scope throws', () => {
      expect(() =>
        buildAgentAccessClaims(
          buildInput({ scope: 'ADMIN' as unknown as 'AGENT' }),
        ),
      ).toThrow(RangeError);
    });

    it.each([0, -1, 1.5, NaN, Infinity])('ttlSeconds %p throws', (ttl) => {
      expect(() =>
        buildAgentAccessClaims(buildInput({ ttlSeconds: ttl })),
      ).toThrow(RangeError);
    });

    it('an invalid now throws', () => {
      expect(() =>
        buildAgentAccessClaims(buildInput({ now: new Date('nope') })),
      ).toThrow(RangeError);
    });

    it.each([
      ['issuer', { issuer: '' }],
      ['audience', { audience: '' }],
    ])('an empty %s throws', (_label, overrides) => {
      expect(() => buildAgentAccessClaims(buildInput(overrides))).toThrow(
        RangeError,
      );
    });
  });
});

describe('validateAgentAccessClaims', () => {
  it('accepts good AGENT claims', () => {
    expect(validateAgentAccessClaims(claims(), expected())).toEqual({
      ok: true,
      claims: claims(),
    });
  });

  it('accepts good APPLICANT claims', () => {
    const c = claims({ sub: 'hash-1', scope: 'APPLICANT' });
    expect(validateAgentAccessClaims(c, expected())).toEqual({
      ok: true,
      claims: c,
    });
  });

  it('drops extra claims from the result', () => {
    const result = validateAgentAccessClaims(
      { ...claims(), jti: 'x', role: 'admin' },
      expected(),
    );
    expect(result).toEqual({ ok: true, claims: claims() });
  });

  describe('MALFORMED', () => {
    it.each([
      ['undefined', undefined],
      ['null', null],
      ['a string', 'eyJ...'],
      ['a number', 42],
      ['an array', [claims()]],
      ['a boolean', true],
    ])('non-object input: %s', (_label, input) => {
      expect(validateAgentAccessClaims(input, expected())).toEqual({
        ok: false,
        reason: 'MALFORMED',
      });
    });

    it.each([
      ['missing sub', { sub: undefined }],
      ['empty sub', { sub: '' }],
      ['numeric sub', { sub: 123 }],
      ['missing scope', { scope: undefined }],
      ['array audience', { aud: [AUD] }],
      ['missing issuer', { iss: undefined }],
      ['string iat', { iat: String(NOW_S) }],
      ['fractional iat', { iat: NOW_S + 0.5 }],
      ['negative iat', { iat: -1 }],
      ['millisecond exp', { exp: (NOW_S + 900) * 1000 + 0.5 }],
      ['missing exp', { exp: undefined }],
      ['exp equal to iat', { exp: NOW_S }],
      ['exp before iat', { exp: NOW_S - 1 }],
    ])('%s', (_label, overrides) => {
      expect(validateAgentAccessClaims(claims(overrides), expected())).toEqual({
        ok: false,
        reason: 'MALFORMED',
      });
    });
  });

  it('WRONG_ISSUER', () => {
    expect(
      validateAgentAccessClaims(claims({ iss: 'someone-else' }), expected()),
    ).toEqual({ ok: false, reason: 'WRONG_ISSUER' });
  });

  it('WRONG_AUDIENCE', () => {
    expect(
      validateAgentAccessClaims(
        claims({ aud: 'nenjam-member-app' }),
        expected(),
      ),
    ).toEqual({ ok: false, reason: 'WRONG_AUDIENCE' });
  });

  describe('EXPIRED (no clock tolerance)', () => {
    const exp = NOW_S + 900;

    it('is valid one millisecond before exp', () => {
      expect(
        validateAgentAccessClaims(claims(), expected(new Date(exp * 1000 - 1)))
          .ok,
      ).toBe(true);
    });

    it('is expired exactly at exp', () => {
      expect(
        validateAgentAccessClaims(claims(), expected(new Date(exp * 1000))),
      ).toEqual({ ok: false, reason: 'EXPIRED' });
    });

    it('is expired after exp', () => {
      expect(
        validateAgentAccessClaims(claims(), expected(new Date(exp * 1000 + 1))),
      ).toEqual({ ok: false, reason: 'EXPIRED' });
    });
  });

  describe('NOT_YET_VALID (no clock tolerance)', () => {
    it('is valid exactly at iat', () => {
      expect(
        validateAgentAccessClaims(claims(), expected(new Date(NOW_S * 1000)))
          .ok,
      ).toBe(true);
    });

    it('is not yet valid one millisecond before iat', () => {
      expect(
        validateAgentAccessClaims(
          claims(),
          expected(new Date(NOW_S * 1000 - 1)),
        ),
      ).toEqual({ ok: false, reason: 'NOT_YET_VALID' });
    });
  });

  it.each(['ADMIN', 'agent', '', 'MEMBER'])('BAD_SCOPE for %p', (scope) => {
    expect(validateAgentAccessClaims(claims({ scope }), expected())).toEqual({
      ok: false,
      reason: 'BAD_SCOPE',
    });
  });

  describe('order of checks', () => {
    it('MALFORMED beats everything', () => {
      expect(
        validateAgentAccessClaims(
          claims({ iat: 'x', iss: 'bad', aud: 'bad', scope: 'BAD' }),
          expected(),
        ),
      ).toEqual({ ok: false, reason: 'MALFORMED' });
    });

    it('WRONG_ISSUER beats WRONG_AUDIENCE, EXPIRED and BAD_SCOPE', () => {
      expect(
        validateAgentAccessClaims(
          claims({ iss: 'bad', aud: 'bad', scope: 'BAD' }),
          expected(new Date((NOW_S + 10_000) * 1000)),
        ),
      ).toEqual({ ok: false, reason: 'WRONG_ISSUER' });
    });

    it('WRONG_AUDIENCE beats EXPIRED and BAD_SCOPE', () => {
      expect(
        validateAgentAccessClaims(
          claims({ aud: 'bad', scope: 'BAD' }),
          expected(new Date((NOW_S + 10_000) * 1000)),
        ),
      ).toEqual({ ok: false, reason: 'WRONG_AUDIENCE' });
    });

    it('EXPIRED beats BAD_SCOPE', () => {
      expect(
        validateAgentAccessClaims(
          claims({ scope: 'BAD' }),
          expected(new Date((NOW_S + 10_000) * 1000)),
        ),
      ).toEqual({ ok: false, reason: 'EXPIRED' });
    });

    it('NOT_YET_VALID beats BAD_SCOPE', () => {
      expect(
        validateAgentAccessClaims(
          claims({ scope: 'BAD' }),
          expected(new Date((NOW_S - 1) * 1000)),
        ),
      ).toEqual({ ok: false, reason: 'NOT_YET_VALID' });
    });
  });

  describe('expected values', () => {
    it('throws on an invalid now', () => {
      expect(() =>
        validateAgentAccessClaims(claims(), expected(new Date('nope'))),
      ).toThrow(RangeError);
    });

    it.each([
      ['issuer', { issuer: '', audience: AUD, now: NOW }],
      ['audience', { issuer: ISS, audience: '', now: NOW }],
    ])('throws on an empty expected %s', (_label, exp) => {
      expect(() => validateAgentAccessClaims(claims(), exp)).toThrow(
        RangeError,
      );
    });
  });
});
