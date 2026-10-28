import {
  AgentOtpPurpose,
  AgentOtpRateLimitError,
  AgentPermissionDeniedError,
} from '../ports/agent-platform-ports';
import { FakeAgentClock } from './fake-agent-infra';
import {
  FakeAgentAudit,
  FakeAgentIdentifierHasher,
  FakeAgentOtp,
  FakeAgentPermission,
  FakeAgentSettings,
} from './fake-agent-platform';

const START = new Date('2026-10-28T10:00:00.000Z');
const PHONE = '+919876543210';
const SIGN_IN = 'AGENT_SIGN_IN' as const;
// Other purposes belong to Shaaz's service; the agent port only names one.
const OTHER_PURPOSE = 'MEMBER_SIGN_IN' as unknown as AgentOtpPurpose;

describe('FakeAgentOtp (AgentOtpPort contract)', () => {
  const make = (
    overrides: Partial<{ maxAttempts: number; sendLimit: number }> = {},
  ) => {
    const clock = new FakeAgentClock(START);
    const otp = new FakeAgentOtp({
      clock,
      ttlMs: 300_000,
      maxAttempts: 3,
      sendLimit: 3,
      sendWindowMs: 600_000,
      ...overrides,
    });
    return { clock, otp };
  };

  it('verifies the right code and returns the phone it was sent to', async () => {
    const { otp } = make();
    const { challengeId } = await otp.send(SIGN_IN, PHONE);
    await expect(
      otp.verify(SIGN_IN, challengeId, otp.codeFor(challengeId)),
    ).resolves.toEqual({ ok: true, phoneE164: PHONE });
  });

  it('a challenge verifies successfully only once', async () => {
    const { otp } = make();
    const { challengeId } = await otp.send(SIGN_IN, PHONE);
    const code = otp.codeFor(challengeId);
    await otp.verify(SIGN_IN, challengeId, code);
    await expect(otp.verify(SIGN_IN, challengeId, code)).resolves.toEqual({
      ok: false,
      reason: 'ALREADY_USED',
    });
  });

  it('a wrong code is INVALID_CODE and does not say what the right one is', async () => {
    const { otp } = make();
    const { challengeId } = await otp.send(SIGN_IN, PHONE);
    const result = await otp.verify(SIGN_IN, challengeId, '000000');
    expect(result).toEqual({ ok: false, reason: 'INVALID_CODE' });
    expect(JSON.stringify(result)).not.toContain(otp.codeFor(challengeId));
  });

  it('is dead after the attempt limit, even for the right code', async () => {
    const { otp } = make({ maxAttempts: 2 });
    const { challengeId } = await otp.send(SIGN_IN, PHONE);
    await otp.verify(SIGN_IN, challengeId, '000000');
    await otp.verify(SIGN_IN, challengeId, '000001');
    await expect(
      otp.verify(SIGN_IN, challengeId, otp.codeFor(challengeId)),
    ).resolves.toEqual({ ok: false, reason: 'TOO_MANY_ATTEMPTS' });
  });

  it('never verifies once expired', async () => {
    const { clock, otp } = make();
    const { challengeId } = await otp.send(SIGN_IN, PHONE);
    clock.advance(300_000);
    await expect(
      otp.verify(SIGN_IN, challengeId, otp.codeFor(challengeId)),
    ).resolves.toEqual({ ok: false, reason: 'EXPIRED' });
  });

  it('reports an unknown challenge as NOT_FOUND', async () => {
    const { otp } = make();
    await expect(otp.verify(SIGN_IN, 'nope', '123456')).resolves.toEqual({
      ok: false,
      reason: 'NOT_FOUND',
    });
  });

  it('keeps challenges independent', async () => {
    const { otp } = make();
    const a = await otp.send(SIGN_IN, PHONE);
    const b = await otp.send(SIGN_IN, 'other-phone');
    expect(a.challengeId).not.toBe(b.challengeId);
    await expect(
      otp.verify(SIGN_IN, a.challengeId, otp.codeFor(b.challengeId)),
    ).resolves.toEqual({ ok: false, reason: 'INVALID_CODE' });
  });

  describe('purpose binding', () => {
    it('a challenge never verifies for another purpose, even with the right code', async () => {
      const { otp } = make();
      const { challengeId } = await otp.send(SIGN_IN, PHONE);
      await expect(
        otp.verify(OTHER_PURPOSE, challengeId, otp.codeFor(challengeId)),
      ).resolves.toEqual({ ok: false, reason: 'NOT_FOUND' });
    });

    it('answers exactly like an unknown challenge, so nothing leaks', async () => {
      const { otp } = make();
      const { challengeId } = await otp.send(SIGN_IN, PHONE);
      const wrongPurpose = await otp.verify(
        OTHER_PURPOSE,
        challengeId,
        '000000',
      );
      const unknown = await otp.verify(OTHER_PURPOSE, 'no-such-id', '000000');
      expect(wrongPurpose).toEqual(unknown);
    });

    it('a wrong-purpose try neither uses up attempts nor consumes the challenge', async () => {
      const { otp } = make({ maxAttempts: 1 });
      const { challengeId } = await otp.send(SIGN_IN, PHONE);
      const code = otp.codeFor(challengeId);
      await otp.verify(OTHER_PURPOSE, challengeId, '000000');
      await otp.verify(OTHER_PURPOSE, challengeId, code);
      await expect(otp.verify(SIGN_IN, challengeId, code)).resolves.toEqual({
        ok: true,
        phoneE164: PHONE,
      });
    });
  });

  describe('rate limit on send (per phone and purpose)', () => {
    it('allows up to the limit, then rejects with a positive integer retryAfterSeconds', async () => {
      const { otp } = make({ sendLimit: 2 });
      await otp.send(SIGN_IN, PHONE);
      await otp.send(SIGN_IN, PHONE);
      const error = await otp.send(SIGN_IN, PHONE).catch((e: unknown) => e);
      expect(error).toBeInstanceOf(AgentOtpRateLimitError);
      const { retryAfterSeconds } = error as AgentOtpRateLimitError;
      expect(Number.isInteger(retryAfterSeconds)).toBe(true);
      expect(retryAfterSeconds).toBeGreaterThan(0);
    });

    it('retryAfterSeconds is the time until the oldest send leaves the window, rounded up', async () => {
      const { clock, otp } = make({ sendLimit: 1 });
      await otp.send(SIGN_IN, PHONE);
      clock.advance(100_500);
      const error = await otp.send(SIGN_IN, PHONE).catch((e: unknown) => e);
      // window 600 s, 100.5 s used: 499.5 s left, rounded up to 500.
      expect((error as AgentOtpRateLimitError).retryAfterSeconds).toBe(500);
    });

    it('a refused send does not use up the allowance or create a challenge', async () => {
      const { clock, otp } = make({ sendLimit: 1 });
      await otp.send(SIGN_IN, PHONE);
      await expect(otp.send(SIGN_IN, PHONE)).rejects.toBeInstanceOf(
        AgentOtpRateLimitError,
      );
      clock.advance(600_000);
      await expect(otp.send(SIGN_IN, PHONE)).resolves.toBeDefined();
    });

    it('resets once the window has passed', async () => {
      const { clock, otp } = make({ sendLimit: 2 });
      await otp.send(SIGN_IN, PHONE);
      await otp.send(SIGN_IN, PHONE);
      await expect(otp.send(SIGN_IN, PHONE)).rejects.toBeInstanceOf(
        AgentOtpRateLimitError,
      );
      clock.advance(600_000);
      await expect(otp.send(SIGN_IN, PHONE)).resolves.toBeDefined();
      await expect(otp.send(SIGN_IN, PHONE)).resolves.toBeDefined();
      await expect(otp.send(SIGN_IN, PHONE)).rejects.toBeInstanceOf(
        AgentOtpRateLimitError,
      );
    });

    it('counts per phone', async () => {
      const { otp } = make({ sendLimit: 1 });
      await otp.send(SIGN_IN, PHONE);
      await expect(otp.send(SIGN_IN, 'other-phone')).resolves.toBeDefined();
    });

    it('counts per purpose', async () => {
      const { otp } = make({ sendLimit: 1 });
      await otp.send(SIGN_IN, PHONE);
      await expect(otp.send(OTHER_PURPOSE, PHONE)).resolves.toBeDefined();
    });

    it('does not stop a challenge that was already sent from verifying', async () => {
      const { otp } = make({ sendLimit: 1 });
      const { challengeId } = await otp.send(SIGN_IN, PHONE);
      await expect(otp.send(SIGN_IN, PHONE)).rejects.toBeInstanceOf(
        AgentOtpRateLimitError,
      );
      await expect(
        otp.verify(SIGN_IN, challengeId, otp.codeFor(challengeId)),
      ).resolves.toMatchObject({ ok: true });
    });
  });
});

describe('AgentOtpRateLimitError', () => {
  it('carries retryAfterSeconds', () => {
    const error = new AgentOtpRateLimitError(30);
    expect(error.retryAfterSeconds).toBe(30);
    expect(error).toBeInstanceOf(Error);
  });

  it.each([0, -1, 1.5, NaN, Infinity])(
    'refuses %p as retryAfterSeconds',
    (value) => {
      expect(() => new AgentOtpRateLimitError(value)).toThrow(RangeError);
    },
  );
});

describe('FakeAgentSettings (AgentSettingsPort contract)', () => {
  it('returns only keys that are requested and set', async () => {
    const settings = new FakeAgentSettings({ a: 1, b: 2, c: 3 });
    await expect(settings.getMany(['a', 'c', 'missing'])).resolves.toEqual({
      a: 1,
      c: 3,
    });
  });

  it('keeps a stored null as a value, and a removed key as absent', async () => {
    const settings = new FakeAgentSettings({ a: null, b: 1 });
    settings.remove('b');
    const result = await settings.getMany(['a', 'b']);
    expect(Object.prototype.hasOwnProperty.call(result, 'a')).toBe(true);
    expect(result.a).toBeNull();
    expect(Object.prototype.hasOwnProperty.call(result, 'b')).toBe(false);
  });
});

describe('FakeAgentIdentifierHasher (AgentIdentifierHasher contract)', () => {
  const hasher = new FakeAgentIdentifierHasher('test-secret');

  it('is deterministic and version-prefixed', () => {
    const hash = hasher.hash('PHONE', PHONE);
    expect(hash).toBe(hasher.hash('PHONE', PHONE));
    expect(hash).toMatch(/^v1:[0-9a-f]{64}$/);
  });

  it('gives the same hash for two spellings of one email', () => {
    expect(hasher.hash('EMAIL', 'Ravi@OkBank')).toBe(
      hasher.hash('EMAIL', '  ravi@okbank '),
    );
  });

  it('gives the same hash for two spellings of one PAN', () => {
    expect(hasher.hash('PAN', 'abcde1234f')).toBe(
      hasher.hash('PAN', ' ABCDE1234F  '),
    );
  });

  it('trims a phone but does not change its case or validate it', () => {
    expect(hasher.hash('PHONE', ` ${PHONE} `)).toBe(
      hasher.hash('PHONE', PHONE),
    );
    expect(() => hasher.hash('PHONE', 'not-a-phone')).not.toThrow();
  });

  it('differs by kind, even for the same text', () => {
    const text = 'abcde1234f';
    const hashes = new Set([
      hasher.hash('PHONE', text),
      hasher.hash('EMAIL', text),
      hasher.hash('PAN', text),
    ]);
    expect(hashes.size).toBe(3);
  });

  it('differs by value and by secret', () => {
    expect(hasher.hash('PHONE', PHONE)).not.toBe(
      hasher.hash('PHONE', 'other-phone'),
    );
    expect(hasher.hash('PHONE', PHONE)).not.toBe(
      new FakeAgentIdentifierHasher('other').hash('PHONE', PHONE),
    );
  });

  it('never contains the input, raw or normalised', () => {
    const cases: Array<['PHONE' | 'EMAIL' | 'PAN', string]> = [
      ['PHONE', PHONE],
      ['EMAIL', 'Ravi@OkBank'],
      ['PAN', 'abcde1234f'],
    ];
    for (const [kind, value] of cases) {
      const hash = hasher.hash(kind, value).toLowerCase();
      expect(hash).not.toContain(value.toLowerCase());
      expect(hash).not.toContain(value.trim().toLowerCase().replace(/\+/g, ''));
    }
    expect(hasher.hash('PHONE', PHONE)).not.toContain('9876543210');
  });

  it('refuses an empty or whitespace-only value, and an empty secret', () => {
    expect(() => hasher.hash('PHONE', '')).toThrow(RangeError);
    expect(() => hasher.hash('EMAIL', '   ')).toThrow(RangeError);
    expect(() => new FakeAgentIdentifierHasher('')).toThrow(RangeError);
  });
});

describe('FakeAgentPermission (AgentPermissionPort contract)', () => {
  const perm = { module: 'agents', action: 'approve' };

  it('allows a granted permission', async () => {
    const port = new FakeAgentPermission();
    port.grant('admin-1', perm);
    await expect(port.assert('admin-1', perm)).resolves.toBeUndefined();
  });

  it('denies another action, another module, another actor and no grant', async () => {
    const port = new FakeAgentPermission();
    port.grant('admin-1', perm);
    for (const [actor, p] of [
      ['admin-1', { module: 'agents', action: 'reject' }],
      ['admin-1', { module: 'payouts', action: 'approve' }],
      ['admin-2', perm],
    ] as const) {
      await expect(port.assert(actor, p)).rejects.toBeInstanceOf(
        AgentPermissionDeniedError,
      );
    }
  });

  it('always denies an empty actor id', async () => {
    const port = new FakeAgentPermission();
    port.grant('', perm);
    await expect(port.assert('', perm)).rejects.toBeInstanceOf(
      AgentPermissionDeniedError,
    );
  });
});

describe('FakeAgentAudit (AgentAuditPort contract)', () => {
  it('keeps entries in order', async () => {
    const audit = new FakeAgentAudit();
    await audit.record({
      actorId: 'a',
      action: 'X',
      entity: 'agent',
      entityId: '1',
    });
    await audit.record({
      actorId: null,
      action: 'Y',
      entity: 'agent',
      entityId: null,
    });
    expect(audit.entries.map((e) => e.action)).toEqual(['X', 'Y']);
  });

  it('is not changed by editing the object afterwards or the returned list', async () => {
    const audit = new FakeAgentAudit();
    const entry = {
      actorId: 'a',
      action: 'X',
      entity: 'agent',
      entityId: '1',
      metadata: { n: 1 },
    };
    await audit.record(entry);
    entry.metadata.n = 2;
    (audit.entries[0].metadata as { n: number }).n = 3;
    expect(audit.entries[0].metadata).toEqual({ n: 1 });
  });

  it('refuses an empty action or entity and stores nothing', async () => {
    const audit = new FakeAgentAudit();
    await expect(
      audit.record({ actorId: null, action: '', entity: 'e', entityId: null }),
    ).rejects.toThrow(RangeError);
    await expect(
      audit.record({ actorId: null, action: 'a', entity: '', entityId: null }),
    ).rejects.toThrow(RangeError);
    expect(audit.entries).toHaveLength(0);
  });
});
