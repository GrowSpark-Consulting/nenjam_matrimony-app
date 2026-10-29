import { createHash, randomBytes, randomInt } from 'node:crypto';

/**
 * Opaque tokens and one-time codes for staff sign-in. (Encryption at rest of
 * the TOTP secret is the shared SecretSealer in @app/common.)
 */

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
