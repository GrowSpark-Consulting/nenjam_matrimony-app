/**
 * AES-256-GCM implementation of `AgentSecretSealer`, with `node:crypto` only.
 *
 * Output: "v1:" + base64url( iv(12) | auth tag(16) | ciphertext ). The key is
 * a parameter: this file reads no environment and holds no key. It never logs
 * and never puts the plaintext or the key in an error message.
 */
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import type { AgentSecretSealer } from '../ports/agent-secret-sealer.port';

const VERSION_PREFIX = 'v1:';
const KEY_BYTES = 32;
const IV_BYTES = 12;
const TAG_BYTES = 16;

export class AesGcmSecretSealer implements AgentSecretSealer {
  private readonly key: Buffer;

  constructor(key: Buffer) {
    if (!Buffer.isBuffer(key) || key.length !== KEY_BYTES) {
      throw new RangeError(`The sealing key must be ${KEY_BYTES} bytes.`);
    }
    // A private copy, so editing the caller's buffer cannot change the key.
    this.key = Buffer.from(key);
  }

  seal(plaintext: string): string {
    if (typeof plaintext !== 'string' || plaintext.length === 0) {
      throw new RangeError('plaintext must be a non-empty string.');
    }
    const iv = randomBytes(IV_BYTES);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const encrypted = Buffer.concat([
      cipher.update(plaintext, 'utf8'),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag();
    return `${VERSION_PREFIX}${Buffer.concat([iv, tag, encrypted]).toString('base64url')}`;
  }

  open(sealed: string): string {
    if (typeof sealed !== 'string' || !sealed.startsWith(VERSION_PREFIX)) {
      throw new Error('The sealed value is not in a supported format.');
    }
    const raw = Buffer.from(sealed.slice(VERSION_PREFIX.length), 'base64url');
    if (raw.length <= IV_BYTES + TAG_BYTES) {
      throw new Error('The sealed value is not in a supported format.');
    }
    const iv = raw.subarray(0, IV_BYTES);
    const tag = raw.subarray(IV_BYTES, IV_BYTES + TAG_BYTES);
    const encrypted = raw.subarray(IV_BYTES + TAG_BYTES);
    try {
      const decipher = createDecipheriv('aes-256-gcm', this.key, iv);
      decipher.setAuthTag(tag);
      return Buffer.concat([
        decipher.update(encrypted),
        decipher.final(),
      ]).toString('utf8');
    } catch {
      // The library's message is dropped on purpose: it adds nothing safe.
      throw new Error('The sealed value could not be opened.');
    }
  }
}
