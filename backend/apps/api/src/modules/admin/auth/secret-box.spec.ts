import { randomBytes } from 'node:crypto';
import {
  hashEnrollmentCode,
  hashOpaqueToken,
  newEnrollmentCode,
  newOpaqueToken,
  open,
  parseSecretKey,
  seal,
} from './secret-box';

describe('secret-box', () => {
  const key = randomBytes(32);

  it('seals and opens a value; the sealed form does not contain it', () => {
    const sealed = seal(key, 'JBSWY3DPEHPK3PXP');
    expect(sealed.startsWith('v1.')).toBe(true);
    expect(sealed).not.toContain('JBSWY3DPEHPK3PXP');
    expect(open(key, sealed)).toBe('JBSWY3DPEHPK3PXP');
    // A fresh IV every time.
    expect(seal(key, 'JBSWY3DPEHPK3PXP')).not.toBe(sealed);
  });

  it('refuses a tampered value or the wrong key', () => {
    const sealed = seal(key, 'secret');
    const parts = sealed.split('.');
    const flipped = Buffer.from(parts[3], 'base64url');
    flipped[0] ^= 1;
    parts[3] = flipped.toString('base64url');
    expect(() => open(key, parts.join('.'))).toThrow();
    expect(() => open(randomBytes(32), sealed)).toThrow();
    expect(() => open(key, 'v2.a.b.c')).toThrow('Unrecognised');
  });

  it('parses a 32-byte base64 key, treats blank as unset, rejects other lengths', () => {
    expect(parseSecretKey(key.toString('base64'))).toEqual(key);
    expect(parseSecretKey(undefined)).toBeNull();
    expect(parseSecretKey('  ')).toBeNull();
    expect(() => parseSecretKey(randomBytes(16).toString('base64'))).toThrow(
      'ADMIN_MFA_ENCRYPTION_KEY',
    );
  });

  it('issues unguessable tokens and stores only their hash', () => {
    const token = newOpaqueToken();
    expect(token).toMatch(/^[\w-]{43}$/);
    expect(hashOpaqueToken(token)).toMatch(/^[0-9a-f]{64}$/);
    expect(hashOpaqueToken(token)).not.toContain(token);
    expect(newOpaqueToken()).not.toBe(token);
  });

  it('issues readable enrolment codes whose hash ignores case, spaces and dashes', () => {
    const code = newEnrollmentCode();
    expect(code).toMatch(/^[2-9A-HJKMNP-Z]{5}-[2-9A-HJKMNP-Z]{5}$/);
    const typed = ` ${code.toLowerCase().replace('-', ' ')} `;
    expect(hashEnrollmentCode(typed)).toBe(hashEnrollmentCode(code));
    expect(hashEnrollmentCode('AAAAA-AAAAA')).not.toBe(
      hashEnrollmentCode(code),
    );
  });
});
