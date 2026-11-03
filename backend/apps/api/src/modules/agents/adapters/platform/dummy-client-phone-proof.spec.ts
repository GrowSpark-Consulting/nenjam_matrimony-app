import { AgentOtpRateLimitError } from '../../ports/agent-platform-ports';
import { FakeAgentClientConsentCodeStore } from '../../testing/fake-agent-clients';
import { FakeAgentClock } from '../../testing/fake-agent-infra';
import {
  FakeAgentIdentifierHasher,
  FakeAgentOtp,
} from '../../testing/fake-agent-platform';
import {
  DummyClientPhoneProof,
  type ClientDummyCodeConfig,
} from './dummy-client-phone-proof';

const APPROVED = '+919000000001';
const OTHER = '+919000000002';
const NOW = new Date('2026-11-03T10:00:00.000Z');

function make(
  config: Partial<ClientDummyCodeConfig> = {},
  hasher = new FakeAgentIdentifierHasher('pepper-new', ['pepper-old']),
) {
  const clock = new FakeAgentClock(NOW);
  const otp = new FakeAgentOtp({
    clock,
    ttlMs: 300_000,
    maxAttempts: 5,
    sendLimit: 2,
    sendWindowMs: 3_600_000,
  });
  const codes = new FakeAgentClientConsentCodeStore();
  const proof = new DummyClientPhoneProof({
    otp,
    codes,
    hasher,
    config: {
      dummyEnabled: true,
      dummyPhones: [APPROVED],
      dummyCode: '000000',
      ...config,
    },
  });
  const send = jest.spyOn(otp, 'send');
  return { clock, otp, codes, proof, hasher, send };
}

describe('DummyClientPhoneProof.canReach', () => {
  it('only an explicitly approved test number, with the dummy code on and set', () => {
    expect(make().proof.canReach(APPROVED)).toBe(true);
    expect(make().proof.canReach(OTHER)).toBe(false);
    expect(make({ dummyEnabled: false }).proof.canReach(APPROVED)).toBe(false);
    expect(make({ dummyCode: undefined }).proof.canReach(APPROVED)).toBe(false);
    expect(make({ dummyCode: '' }).proof.canReach(APPROVED)).toBe(false);
  });

  it("an empty list reaches NO phone (the OTP service's any-phone mode is ignored)", () => {
    const { proof } = make({ dummyPhones: [] });
    expect(proof.canReach(APPROVED)).toBe(false);
    expect(proof.canReach(OTHER)).toBe(false);
  });
});

describe('DummyClientPhoneProof.send', () => {
  it('refuses a phone it cannot reach without calling the OTP service', async () => {
    const { proof, send } = make();
    await expect(proof.send(OTHER)).rejects.toMatchObject({
      name: 'AgentServiceError',
      code: 'OTP_DELIVERY_UNAVAILABLE',
    });
    expect(send).not.toHaveBeenCalled();
  });

  it('sends for the AGENT_CLIENT_CONSENT purpose and remembers the newest code under the newest hash', async () => {
    const { proof, send, codes, hasher } = make();
    const first = await proof.send(APPROVED);
    expect(send).toHaveBeenCalledWith('AGENT_CLIENT_CONSENT', APPROVED);
    expect(first.expiresAt).toEqual(new Date(NOW.getTime() + 300_000));
    await proof.send(APPROVED);
    const pointer = await codes.find([hasher.hash('PHONE', APPROVED)]);
    expect(pointer?.challengeId).toBe('challenge-2');
    expect(codes.size()).toBe(1);
  });

  it('passes a rate limit through', async () => {
    const { proof } = make();
    await proof.send(APPROVED);
    await proof.send(APPROVED);
    await expect(proof.send(APPROVED)).rejects.toBeInstanceOf(
      AgentOtpRateLimitError,
    );
  });
});

describe('DummyClientPhoneProof.verify', () => {
  const code = (p: { otp: FakeAgentOtp }, challengeId: string) =>
    p.otp.codeFor(challengeId);

  it('checks the newest code sent to the phone, once', async () => {
    const w = make();
    await w.proof.send(APPROVED);
    await w.proof.send(APPROVED);
    expect(
      await w.proof.verify({
        kind: 'CODE',
        phoneE164: APPROVED,
        code: code(w, 'challenge-1'),
      }),
    ).toEqual({ ok: false, reason: 'INVALID_CODE' });
    expect(
      await w.proof.verify({
        kind: 'CODE',
        phoneE164: APPROVED,
        code: code(w, 'challenge-2'),
      }),
    ).toEqual({ ok: true, phoneE164: APPROVED });
    // Used up: the pointer is gone.
    expect(
      await w.proof.verify({
        kind: 'CODE',
        phoneE164: APPROVED,
        code: code(w, 'challenge-2'),
      }),
    ).toEqual({ ok: false, reason: 'NOT_FOUND' });
  });

  it('an unknown phone, an expired code and a too-late phone', async () => {
    const w = make();
    expect(
      await w.proof.verify({
        kind: 'CODE',
        phoneE164: APPROVED,
        code: '000000',
      }),
    ).toEqual({ ok: false, reason: 'NOT_FOUND' });
    await w.proof.send(APPROVED);
    w.clock.advance(300_000);
    expect(
      await w.proof.verify({
        kind: 'CODE',
        phoneE164: APPROVED,
        code: code(w, 'challenge-1'),
      }),
    ).toEqual({ ok: false, reason: 'EXPIRED' });
  });

  it('a phone taken off the approved list no longer verifies, even with a live code', async () => {
    const hasher = new FakeAgentIdentifierHasher('pepper-new');
    const before = make({}, hasher);
    await before.proof.send(APPROVED);
    const after = new DummyClientPhoneProof({
      otp: before.otp,
      codes: before.codes,
      hasher,
      config: { dummyEnabled: true, dummyPhones: [OTHER], dummyCode: '000000' },
    });
    expect(
      await after.verify({
        kind: 'CODE',
        phoneE164: APPROVED,
        code: before.otp.codeFor('challenge-1'),
      }),
    ).toEqual({ ok: false, reason: 'NOT_FOUND' });
  });

  it('finds a code remembered under an older pepper version', async () => {
    const w = make();
    await w.proof.send(APPROVED);
    const [newest, older] = w.hasher.hashAll('PHONE', APPROVED);
    const pointer = await w.codes.find([newest]);
    await w.codes.delete([newest]);
    await w.codes.save({ ...pointer!, phoneHash: older });
    expect(
      await w.proof.verify({
        kind: 'CODE',
        phoneE164: APPROVED,
        code: w.otp.codeFor('challenge-1'),
      }),
    ).toEqual({ ok: true, phoneE164: APPROVED });
    expect(await w.codes.find([older])).toBeNull();
  });

  it('a sign-in code (another purpose) never verifies as consent', async () => {
    const w = make();
    const signIn = await w.otp.send('AGENT_SIGN_IN', APPROVED);
    await w.codes.save({
      phoneHash: w.hasher.hash('PHONE', APPROVED),
      challengeId: signIn.challengeId,
      expiresAt: signIn.expiresAt,
    });
    expect(
      await w.proof.verify({
        kind: 'CODE',
        phoneE164: APPROVED,
        code: w.otp.codeFor(signIn.challengeId),
      }),
    ).toEqual({ ok: false, reason: 'NOT_FOUND' });
  });

  it('a Firebase ID token is not supported yet', async () => {
    expect(
      await make().proof.verify({ kind: 'FIREBASE_ID_TOKEN', idToken: 'x' }),
    ).toEqual({ ok: false, reason: 'UNSUPPORTED' });
  });
});
