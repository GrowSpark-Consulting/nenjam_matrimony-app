import { AGENT_SEAL_PURPOSES } from '../ports/agent-secret-sealer.port';
import { AgentPiiSealer } from './agent-pii-sealer';

// Test-only keys, not secrets.
const KEY = Buffer.alloc(32, 1);
const OTHER_KEY = Buffer.alloc(32, 2);
const { pan, payoutDetails, applicantPhone } = AGENT_SEAL_PURPOSES;

describe('AgentPiiSealer', () => {
  const sealer = new AgentPiiSealer(KEY);

  it('uses the three agreed purpose names', () => {
    expect(Object.values(AGENT_SEAL_PURPOSES).sort()).toEqual([
      'agent.applicant_phone',
      'agent.pan',
      'agent.payout_details',
    ]);
  });

  it.each([pan, payoutDetails, applicantPhone])(
    'opens what it sealed for %s, including unicode and long text',
    (purpose) => {
      for (const text of ['ABCDE1234F', 'ரவி குமார்', 'x'.repeat(5000)]) {
        expect(sealer.open(purpose, sealer.seal(purpose, text))).toBe(text);
      }
    },
  );

  it('never contains the plaintext and differs on every seal', () => {
    const sealed = sealer.seal(pan, 'ABCDE1234F');
    expect(sealed).not.toContain('ABCDE1234F');
    expect(
      Buffer.from(sealed.slice(3), 'base64url').toString('latin1'),
    ).not.toContain('ABCDE1234F');
    expect(sealer.seal(pan, 'same')).not.toBe(sealer.seal(pan, 'same'));
  });

  it('does not open a value under another purpose (all six pairings)', () => {
    const purposes = [pan, payoutDetails, applicantPhone];
    for (const sealedFor of purposes) {
      const sealed = sealer.seal(sealedFor, 'ABCDE1234F');
      for (const openAs of purposes.filter((p) => p !== sealedFor)) {
        expect(() => sealer.open(openAs, sealed)).toThrow(
          'The sealed value could not be opened.',
        );
      }
    }
  });

  it('rejects text altered after sealing and text sealed with another key', () => {
    const sealed = sealer.seal(pan, 'ABCDE1234F');
    const raw = Buffer.from(sealed.slice(3), 'base64url');
    raw[raw.length - 1] ^= 1;
    expect(() => sealer.open(pan, `v1:${raw.toString('base64url')}`)).toThrow(
      'could not be opened',
    );
    expect(() =>
      sealer.open(pan, new AgentPiiSealer(OTHER_KEY).seal(pan, 'ABCDE1234F')),
    ).toThrow('could not be opened');
  });

  it.each(['', 'ABCDE1234F', 'v2:abc', 'v1:', 'v1:AAAA', 'v1:!!!!'])(
    'rejects the malformed value %p',
    (value) => {
      expect(() => sealer.open(pan, value)).toThrow(Error);
    },
  );

  it('refuses an unknown purpose and an empty plaintext', () => {
    expect(() => sealer.seal('agent.other' as never, 'x')).toThrow(RangeError);
    expect(() => sealer.open('agent.other' as never, 'v1:x')).toThrow(
      RangeError,
    );
    expect(() => sealer.seal(pan, '')).toThrow(RangeError);
  });

  it('refuses a key that is not 32 bytes, and keeps no reference to the caller buffer', () => {
    expect(() => new AgentPiiSealer(Buffer.alloc(16))).toThrow(RangeError);
    const key = Buffer.alloc(32, 3);
    const s = new AgentPiiSealer(key);
    const sealed = s.seal(pan, 'ABCDE1234F');
    key.fill(9);
    expect(s.open(pan, sealed)).toBe('ABCDE1234F');
  });

  it('error messages never contain the plaintext or the key', () => {
    const sealed = sealer.seal(pan, 'ABCDE1234F');
    try {
      sealer.open(payoutDetails, sealed);
    } catch (e) {
      const m = (e as Error).message;
      expect(m).not.toContain('ABCDE1234F');
      expect(m).not.toContain(KEY.toString('base64'));
    }
  });
});
