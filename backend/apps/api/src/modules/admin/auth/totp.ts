import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

/**
 * Time-based one-time passwords (RFC 6238 over RFC 4226), the format every
 * authenticator app speaks: HMAC-SHA1, 6 digits, 30-second steps.
 *
 * Written against node:crypto rather than a package because it is forty lines
 * of arithmetic that the RFC's own test vectors pin exactly (totp.spec.ts).
 */
export const TOTP_PERIOD_SECONDS = 30;
export const TOTP_DIGITS = 6;
/** Steps either side of now still accepted — phone clocks drift. */
export const TOTP_WINDOW = 1;

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32Encode(bytes: Buffer): string {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  return out;
}

/** Tolerates lower case, spaces and `=` padding; throws on anything else. */
export function base32Decode(text: string): Buffer {
  const clean = text.replace(/[\s=]/g, '').toUpperCase();
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const char of clean) {
    const index = BASE32_ALPHABET.indexOf(char);
    if (index < 0) throw new RangeError('Invalid base32 character.');
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

/** A new shared secret: 160 random bits (RFC 4226's recommendation), base32. */
export function generateTotpSecret(): string {
  return base32Encode(randomBytes(20));
}

export function totpStep(nowMs: number): number {
  return Math.floor(nowMs / 1000 / TOTP_PERIOD_SECONDS);
}

/** RFC 4226 HOTP for one counter value. */
export function hotp(
  secret: Buffer,
  counter: number,
  digits = TOTP_DIGITS,
): string {
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(counter));
  const mac = createHmac('sha1', secret).update(message).digest();
  const offset = mac[mac.length - 1] & 0x0f;
  const binary =
    ((mac[offset] & 0x7f) << 24) |
    (mac[offset + 1] << 16) |
    (mac[offset + 2] << 8) |
    mac[offset + 3];
  return String(binary % 10 ** digits).padStart(digits, '0');
}

/**
 * The time step [code] is valid for, within the drift window around
 * [nowMs], or null. Every candidate is compared in constant time, and all of
 * them are always compared, so timing says nothing about which (if any)
 * matched. Replay protection — refusing a step already used — is the
 * caller's, because only the caller knows the last accepted step.
 */
export function matchTotp(
  secretBase32: string,
  code: string,
  nowMs: number,
): number | null {
  if (!/^\d{6}$/.test(code)) return null;
  const secret = base32Decode(secretBase32);
  const given = Buffer.from(code);
  const current = totpStep(nowMs);
  let matched: number | null = null;
  for (
    let step = current - TOTP_WINDOW;
    step <= current + TOTP_WINDOW;
    step++
  ) {
    const expected = Buffer.from(hotp(secret, step));
    if (timingSafeEqual(expected, given) && matched === null) matched = step;
  }
  return matched;
}

/** The `otpauth://` URI authenticator apps import (usually as a QR code). */
export function otpauthUri(params: {
  secret: string;
  accountName: string;
  issuer: string;
}): string {
  const label = encodeURIComponent(`${params.issuer}:${params.accountName}`);
  const query = new URLSearchParams({
    secret: params.secret,
    issuer: params.issuer,
    algorithm: 'SHA1',
    digits: String(TOTP_DIGITS),
    period: String(TOTP_PERIOD_SECONDS),
  });
  return `otpauth://totp/${label}?${query.toString()}`;
}
