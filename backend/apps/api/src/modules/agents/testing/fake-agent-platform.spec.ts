import { AgentPermissionDeniedError } from '../ports/agent-platform-ports';
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

describe('FakeAgentOtp (AgentOtpPort contract)', () => {
  const make = (maxAttempts = 3) => {
    const clock = new FakeAgentClock(START);
    const otp = new FakeAgentOtp({ clock, ttlMs: 300_000, maxAttempts });
    return { clock, otp };
  };

  it('verifies the right code and returns the phone it was sent to', async () => {
    const { otp } = make();
    const { challengeId } = await otp.send('AGENT_SIGN_IN', PHONE);
    await expect(
      otp.verify(challengeId, otp.codeFor(challengeId)),
    ).resolves.toEqual({ ok: true, phoneE164: PHONE });
  });

  it('a challenge verifies successfully only once', async () => {
    const { otp } = make();
    const { challengeId } = await otp.send('AGENT_SIGN_IN', PHONE);
    const code = otp.codeFor(challengeId);
    await otp.verify(challengeId, code);
    await expect(otp.verify(challengeId, code)).resolves.toEqual({
      ok: false,
      reason: 'ALREADY_USED',
    });
  });

  it('a wrong code is INVALID_CODE and does not say what the right one is', async () => {
    const { otp } = make();
    const { challengeId } = await otp.send('AGENT_SIGN_IN', PHONE);
    const result = await otp.verify(challengeId, '000000');
    expect(result).toEqual({ ok: false, reason: 'INVALID_CODE' });
    expect(JSON.stringify(result)).not.toContain(otp.codeFor(challengeId));
  });

  it('is dead after the attempt limit, even for the right code', async () => {
    const { otp } = make(2);
    const { challengeId } = await otp.send('AGENT_SIGN_IN', PHONE);
    await otp.verify(challengeId, '000000');
    await otp.verify(challengeId, '000001');
    await expect(
      otp.verify(challengeId, otp.codeFor(challengeId)),
    ).resolves.toEqual({ ok: false, reason: 'TOO_MANY_ATTEMPTS' });
  });

  it('never verifies once expired', async () => {
    const { clock, otp } = make();
    const { challengeId } = await otp.send('AGENT_SIGN_IN', PHONE);
    clock.advance(300_000);
    await expect(
      otp.verify(challengeId, otp.codeFor(challengeId)),
    ).resolves.toEqual({ ok: false, reason: 'EXPIRED' });
  });

  it('reports an unknown challenge as NOT_FOUND', async () => {
    const { otp } = make();
    await expect(otp.verify('nope', '123456')).resolves.toEqual({
      ok: false,
      reason: 'NOT_FOUND',
    });
  });

  it('keeps challenges independent', async () => {
    const { otp } = make();
    const a = await otp.send('AGENT_SIGN_IN', PHONE);
    const b = await otp.send('AGENT_SIGN_IN', 'other-phone');
    expect(a.challengeId).not.toBe(b.challengeId);
    await expect(
      otp.verify(a.challengeId, otp.codeFor(b.challengeId)),
    ).resolves.toEqual({ ok: false, reason: 'INVALID_CODE' });
  });
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

  it('is deterministic', () => {
    expect(hasher.hash('PHONE', PHONE)).toBe(hasher.hash('PHONE', PHONE));
  });

  it('differs by kind and by value', () => {
    expect(hasher.hash('PHONE', PHONE)).not.toBe(hasher.hash('EMAIL', PHONE));
    expect(hasher.hash('PHONE', PHONE)).not.toBe(
      hasher.hash('PHONE', 'other-phone'),
    );
  });

  it('differs by secret', () => {
    expect(hasher.hash('PHONE', PHONE)).not.toBe(
      new FakeAgentIdentifierHasher('other').hash('PHONE', PHONE),
    );
  });

  it('does not contain the input', () => {
    expect(hasher.hash('PHONE', PHONE)).not.toContain('9876543210');
  });

  it('refuses an empty value or secret', () => {
    expect(() => hasher.hash('PHONE', '')).toThrow(RangeError);
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
