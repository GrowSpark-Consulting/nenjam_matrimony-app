import {
  base32Decode,
  base32Encode,
  generateTotpSecret,
  hotp,
  matchTotp,
  otpauthUri,
  totpStep,
} from './totp';

describe('totp', () => {
  // RFC 6238 appendix B, SHA-1: secret "12345678901234567890", 8 digits.
  const RFC_SECRET = Buffer.from('12345678901234567890', 'ascii');
  it.each([
    [59, '94287082'],
    [1111111109, '07081804'],
    [1111111111, '14050471'],
    [1234567890, '89005924'],
    [2000000000, '69279037'],
    [20000000000, '65353130'],
  ])('matches the RFC 6238 vector at T=%i', (seconds, expected) => {
    expect(hotp(RFC_SECRET, totpStep(seconds * 1000), 8)).toBe(expected);
  });

  it('round-trips base32 and tolerates case, spaces and padding', () => {
    const bytes = Buffer.from('12345678901234567890', 'ascii');
    const encoded = base32Encode(bytes);
    expect(encoded).toBe('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
    expect(
      base32Decode(encoded.toLowerCase().replace(/(.{4})/g, '$1 ') + '=='),
    ).toEqual(bytes);
    expect(() => base32Decode('ABC1')).toThrow(RangeError);
  });

  it('generates a 160-bit base32 secret', () => {
    const secret = generateTotpSecret();
    expect(secret).toMatch(/^[A-Z2-7]{32}$/);
    expect(base32Decode(secret)).toHaveLength(20);
    expect(generateTotpSecret()).not.toBe(secret);
  });

  describe('matchTotp', () => {
    const secret = base32Encode(RFC_SECRET);
    const now = 1_700_000_000_000;
    const step = totpStep(now);
    const codeAt = (s: number) => hotp(RFC_SECRET, s);

    it('accepts the current step and one either side, returning the step', () => {
      expect(matchTotp(secret, codeAt(step), now)).toBe(step);
      expect(matchTotp(secret, codeAt(step - 1), now)).toBe(step - 1);
      expect(matchTotp(secret, codeAt(step + 1), now)).toBe(step + 1);
    });

    it('refuses codes outside the drift window', () => {
      expect(matchTotp(secret, codeAt(step - 2), now)).toBeNull();
      expect(matchTotp(secret, codeAt(step + 2), now)).toBeNull();
    });

    it('refuses anything that is not six digits', () => {
      for (const bad of ['', '12345', '1234567', 'abcdef', ' 123456']) {
        expect(matchTotp(secret, bad, now)).toBeNull();
      }
    });
  });

  it('builds an otpauth URI authenticator apps accept', () => {
    const uri = otpauthUri({
      secret: 'ABCDEFGHIJKLMNOP',
      accountName: 'ops@example.com',
      issuer: 'Nenjam Admin',
    });
    expect(uri).toBe(
      'otpauth://totp/Nenjam%20Admin%3Aops%40example.com?secret=ABCDEFGHIJKLMNOP&issuer=Nenjam+Admin&algorithm=SHA1&digits=6&period=30',
    );
  });
});
