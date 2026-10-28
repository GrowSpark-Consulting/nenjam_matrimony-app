import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  randomInt,
} from 'node:crypto';

/**
 * Encryption at rest for admin TOTP secrets (AES-256-GCM).
 *
 * A database copy alone must not be enough to mint an admin's codes, so the
 * secret is stored sealed under ADMIN_MFA_ENCRYPTION_KEY, which lives only in
 * the API's environment. Generate one with:
 *
 *   node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
 *
 * Format: `v1.<iv>.<tag>.<ciphertext>`, each part base64url. The version
 * prefix leaves room to rotate the key or algorithm later.
 */
const VERSION = 'v1';

/** The 32-byte key, or null when unset. Throws on a malformed value — a
 *  wrong-length key is a configuration error, not "MFA off". */
export function parseSecretKey(raw: string | undefined): Buffer | null {
  const trimmed = raw?.trim();
  if (!trimmed) return null;
  const key = Buffer.from(trimmed, 'base64');
  if (key.length !== 32) {
    throw new Error(
      'ADMIN_MFA_ENCRYPTION_KEY must be 32 random bytes, base64-encoded.',
    );
  }
  return key;
}

export function seal(key: Buffer, plaintext: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);
  return [
    VERSION,
    iv.toString('base64url'),
    cipher.getAuthTag().toString('base64url'),
    ciphertext.toString('base64url'),
  ].join('.');
}

/** Throws if [sealed] was not produced by [seal] under this key, or was
 *  altered in any way (GCM authenticates every byte). */
export function open(key: Buffer, sealed: string): string {
  const [version, iv, tag, ciphertext] = sealed.split('.');
  if (version !== VERSION || !iv || !tag || ciphertext === undefined) {
    throw new Error('Unrecognised sealed value.');
  }
  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(iv, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(tag, 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertext, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}

/** A bearer secret for a client to hold: 256 random bits. */
export function newOpaqueToken(): string {
  return randomBytes(32).toString('base64url');
}

/** What is stored in place of a bearer secret. Unsalted SHA-256 is enough
 *  for 256-bit random input — there is nothing to brute-force. */
export function hashOpaqueToken(token: string): string {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}

/**
 * A one-time enrolment code for an operator to read out: 10 characters from
 * an alphabet without look-alikes (no 0/O, 1/I/L), shown as `XXXXX-XXXXX`.
 * ~49 bits, against an endpoint that is rate limited and locks the account
 * after a handful of misses.
 */
const ENROLMENT_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

export function newEnrollmentCode(): string {
  const chars = Array.from(
    { length: 10 },
    () => ENROLMENT_ALPHABET[randomInt(ENROLMENT_ALPHABET.length)],
  ).join('');
  return `${chars.slice(0, 5)}-${chars.slice(5)}`;
}

/** Case, spaces and dashes don't matter when the code is typed back. */
export function hashEnrollmentCode(code: string): string {
  return hashOpaqueToken(code.replace(/[\s-]/g, '').toUpperCase());
}
