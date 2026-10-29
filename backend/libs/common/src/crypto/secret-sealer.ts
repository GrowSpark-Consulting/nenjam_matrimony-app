import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

/**
 * Encryption at rest for small secrets stored in the database — admin TOTP
 * secrets, agent PAN and payout details. One implementation for the whole
 * API (AES-256-GCM, node:crypto only), used with a SEPARATE key per kind of
 * data, so losing or rotating one key never touches the others:
 *
 *   ADMIN_MFA_ENCRYPTION_KEY   admin authenticator secrets   purpose 'admin.mfa.totp_secret'
 *   (agent program's key)      agent PAN / payout details    its own purposes
 *
 * The purpose is bound to every value as GCM additional data: a ciphertext
 * copied from one column into another (or opened with the wrong purpose)
 * fails to open instead of decrypting as the wrong thing.
 *
 * Format: "v1:" + base64url(iv(12) | auth tag(16) | ciphertext) — the agent
 * program's format. This file reads no environment, holds no key of its own,
 * never logs, and never puts plaintext or a key in an error message.
 */
const VERSION_PREFIX = 'v1:';
const KEY_BYTES = 32;
const IV_BYTES = 12;
const TAG_BYTES = 16;

export class SecretSealer {
  private readonly key: Buffer;
  private readonly aad: Buffer;

  constructor(key: Buffer, purpose: string) {
    if (!Buffer.isBuffer(key) || key.length !== KEY_BYTES) {
      throw new RangeError(`The sealing key must be ${KEY_BYTES} bytes.`);
    }
    if (typeof purpose !== 'string' || !/^[a-z][a-z0-9_.]*$/.test(purpose)) {
      throw new RangeError(
        'The sealing purpose must be a dotted lower-case name.',
      );
    }
    // A private copy, so editing the caller's buffer cannot change the key.
    this.key = Buffer.from(key);
    this.aad = Buffer.from(purpose, 'utf8');
  }

  seal(plaintext: string): string {
    if (typeof plaintext !== 'string' || plaintext.length === 0) {
      throw new RangeError('plaintext must be a non-empty string.');
    }
    const iv = randomBytes(IV_BYTES);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    cipher.setAAD(this.aad);
    const encrypted = Buffer.concat([
      cipher.update(plaintext, 'utf8'),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag();
    return `${VERSION_PREFIX}${Buffer.concat([iv, tag, encrypted]).toString('base64url')}`;
  }

  /** Throws unless [sealed] was produced by `seal` with this key and
   *  purpose, unaltered. */
  open(sealed: string): string {
    if (typeof sealed !== 'string' || !sealed.startsWith(VERSION_PREFIX)) {
      throw new Error('The sealed value is not in a supported format.');
    }
    const raw = Buffer.from(sealed.slice(VERSION_PREFIX.length), 'base64url');
    if (raw.length <= IV_BYTES + TAG_BYTES) {
      throw new Error('The sealed value is not in a supported format.');
    }
    try {
      const decipher = createDecipheriv(
        'aes-256-gcm',
        this.key,
        raw.subarray(0, IV_BYTES),
      );
      decipher.setAAD(this.aad);
      decipher.setAuthTag(raw.subarray(IV_BYTES, IV_BYTES + TAG_BYTES));
      return Buffer.concat([
        decipher.update(raw.subarray(IV_BYTES + TAG_BYTES)),
        decipher.final(),
      ]).toString('utf8');
    } catch {
      // The library's message is dropped on purpose: it adds nothing safe.
      throw new Error('The sealed value could not be opened.');
    }
  }
}

/**
 * A 32-byte key from base64 config, or null when unset. Throws on a
 * malformed value — a wrong-length key is a configuration error, not
 * "feature off". Generate one with:
 *
 *   node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
 */
export function parseSealingKey(
  raw: string | undefined,
  envName: string,
): Buffer | null {
  const trimmed = raw?.trim();
  if (!trimmed) return null;
  const key = Buffer.from(trimmed, 'base64');
  if (key.length !== KEY_BYTES) {
    throw new Error(
      `${envName} must be ${KEY_BYTES} random bytes, base64-encoded.`,
    );
  }
  return key;
}
