import { randomBytes } from 'node:crypto';
import { parseSealingKey, SecretSealer } from './secret-sealer';

describe('SecretSealer', () => {
  const key = randomBytes(32);
  const sealer = new SecretSealer(key, 'admin.mfa.totp_secret');

  it('seals and opens; the sealed form never contains the plaintext', () => {
    const sealed = sealer.seal('JBSWY3DPEHPK3PXP');
    expect(sealed).toMatch(/^v1:[\w-]+$/);
    expect(sealed).not.toContain('JBSWY3DPEHPK3PXP');
    expect(sealer.open(sealed)).toBe('JBSWY3DPEHPK3PXP');
    expect(sealer.seal('JBSWY3DPEHPK3PXP')).not.toBe(sealed); // fresh IV
  });

  it('refuses a value sealed for another purpose, even with the same key', () => {
    const pan = new SecretSealer(key, 'agent.pan');
    expect(() => sealer.open(pan.seal('ABCDE1234F'))).toThrow(
      'could not be opened',
    );
  });

  it('refuses a tampered value, a different key and unknown formats', () => {
    const sealed = sealer.seal('secret');
    const raw = Buffer.from(sealed.slice(3), 'base64url');
    raw[raw.length - 1] ^= 1;
    expect(() => sealer.open(`v1:${raw.toString('base64url')}`)).toThrow();
    expect(() =>
      new SecretSealer(randomBytes(32), 'admin.mfa.totp_secret').open(sealed),
    ).toThrow();
    expect(() => sealer.open('v2:abc')).toThrow('not in a supported format');
    expect(() => sealer.open('v1:abc')).toThrow('not in a supported format');
  });

  it('never echoes the key or the plaintext in errors', () => {
    try {
      new SecretSealer(randomBytes(32), 'admin.mfa.totp_secret').open(
        sealer.seal('top-secret-value'),
      );
    } catch (error) {
      expect((error as Error).message).not.toContain('top-secret-value');
      expect((error as Error).message).not.toContain(key.toString('base64'));
    }
  });

  it('validates its inputs', () => {
    expect(() => new SecretSealer(randomBytes(16), 'x')).toThrow(RangeError);
    expect(() => new SecretSealer(key, 'Bad Purpose')).toThrow(RangeError);
    expect(() => sealer.seal('')).toThrow(RangeError);
  });

  it('parses a base64 key; blank is unset; a wrong length is an error', () => {
    expect(parseSealingKey(key.toString('base64'), 'X_KEY')).toEqual(key);
    expect(parseSealingKey(undefined, 'X_KEY')).toBeNull();
    expect(parseSealingKey('  ', 'X_KEY')).toBeNull();
    expect(() =>
      parseSealingKey(randomBytes(16).toString('base64'), 'X_KEY'),
    ).toThrow('X_KEY must be 32 random bytes');
  });
});
