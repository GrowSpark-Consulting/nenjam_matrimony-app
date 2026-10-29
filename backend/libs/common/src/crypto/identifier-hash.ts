import { createHmac } from 'node:crypto';
import { isIP } from 'node:net';

/**
 * Keyed one-way hashes of personal identifiers — phone, email, PAN, IP, UPI
 * id — for
 * lookups and uniqueness without keeping the raw value: "is this phone
 * already attributed?", "has this IP tried too many codes?".
 *
 * HMAC-SHA256 under a secret pepper, with the kind bound into the input (a
 * phone and an email with the same text never collide), written as
 * "<version>:<hex>". Callers pass RAW values: each kind is normalised first,
 * so two spellings of one identifier hash the same.
 *
 * Rotation: IDENTIFIER_HASH_PEPPERS = "v2:<new>,v1:<old>", newest first.
 * `hash` always uses the newest; `hashAll` gives one hash per pepper, for
 * finding rows written before the rotation.
 *
 * This file reads no environment, never logs, and never puts a value or a
 * pepper in an error message.
 */
export type IdentifierKind = 'PHONE' | 'EMAIL' | 'PAN' | 'IP' | 'UPI';

export interface IdentifierPepper {
  /** `v` + digits, e.g. `v1`; the prefix of every hash made with it. */
  version: string;
  secret: Buffer;
}

const VERSION = /^v\d{1,6}$/;
const MIN_SECRET_BYTES = 32;
const E164 = /^\+[1-9]\d{7,14}$/;

export class IdentifierHasher {
  private readonly peppers: readonly IdentifierPepper[];

  /** [peppers] newest first; the first one makes every new hash. */
  constructor(peppers: readonly IdentifierPepper[]) {
    if (peppers.length === 0) {
      throw new RangeError('At least one identifier pepper is required.');
    }
    const versions = new Set<string>();
    for (const pepper of peppers) {
      if (!VERSION.test(pepper.version)) {
        throw new RangeError('A pepper version must look like "v1".');
      }
      if (versions.has(pepper.version)) {
        throw new RangeError(`Pepper version ${pepper.version} is repeated.`);
      }
      if (pepper.secret.length < MIN_SECRET_BYTES) {
        throw new RangeError(
          `Pepper ${pepper.version} must be at least ${MIN_SECRET_BYTES} bytes.`,
        );
      }
      versions.add(pepper.version);
    }
    // Private copies, so editing the caller's buffers cannot change a key.
    this.peppers = peppers.map((p) => ({
      version: p.version,
      secret: Buffer.from(p.secret),
    }));
  }

  /** The hash to store: made with the newest pepper. */
  hash(kind: IdentifierKind, value: string): string {
    return digest(this.peppers[0], kind, normalizeIdentifier(kind, value));
  }

  /** One hash per pepper, newest first — match a stored hash against any. */
  hashAll(kind: IdentifierKind, value: string): string[] {
    const normalized = normalizeIdentifier(kind, value);
    return this.peppers.map((pepper) => digest(pepper, kind, normalized));
  }
}

function digest(
  pepper: IdentifierPepper,
  kind: IdentifierKind,
  normalized: string,
): string {
  const mac = createHmac('sha256', pepper.secret)
    .update(`${kind}\n${normalized}`, 'utf8')
    .digest('hex');
  return `${pepper.version}:${mac}`;
}

/**
 * The canonical form hashed for [kind]. Throws RangeError for a value that is
 * empty after trimming, or is not a phone / IP address at all.
 *
 *  - PHONE: E.164. Spaces, dots, dashes and brackets are dropped; `00` means
 *    `+`; a bare 10-digit number, or one with a leading 0 or 91, is Indian.
 *  - EMAIL: trimmed and lower-cased.
 *  - PAN:   spaces dropped, upper-cased.
 *  - IP:    IPv4 dotted; IPv6 in its canonical compressed form; an
 *    IPv4-mapped IPv6 address (`::ffff:1.2.3.4`) is the IPv4 address.
 *  - UPI:   a UPI id (`name@bank`), trimmed and lower-cased.
 */
export function normalizeIdentifier(
  kind: IdentifierKind,
  value: string,
): string {
  if (typeof value !== 'string') {
    throw new RangeError(`The ${kind} value must be a string.`);
  }
  const trimmed = value.normalize('NFKC').trim();
  if (trimmed.length === 0) {
    throw new RangeError(`The ${kind} value is empty.`);
  }
  switch (kind) {
    case 'PHONE':
      return normalizePhone(trimmed);
    case 'EMAIL':
      return trimmed.toLowerCase();
    case 'PAN':
      return trimmed.replace(/\s+/g, '').toUpperCase();
    case 'IP':
      return normalizeIp(trimmed);
    case 'UPI':
      return normalizeUpi(trimmed);
    default:
      throw new RangeError('Unknown identifier kind.');
  }
}

function normalizePhone(raw: string): string {
  let phone = raw.replace(/[\s().-]/g, '');
  if (phone.startsWith('00')) phone = `+${phone.slice(2)}`;
  else if (/^\d{10}$/.test(phone)) phone = `+91${phone}`;
  else if (/^0\d{10}$/.test(phone)) phone = `+91${phone.slice(1)}`;
  else if (/^91\d{10}$/.test(phone)) phone = `+${phone}`;
  if (!E164.test(phone)) {
    throw new RangeError('The PHONE value is not a phone number.');
  }
  return phone;
}

function normalizeUpi(raw: string): string {
  const upi = raw.toLowerCase();
  if (!/^[a-z0-9._-]{2,256}@[a-z][a-z0-9.-]{1,64}$/.test(upi)) {
    throw new RangeError('The UPI value is not a UPI id.');
  }
  return upi;
}

function normalizeIp(raw: string): string {
  // A zone (fe80::1%eth0) names the local interface, not the address.
  const address = raw.split('%')[0].toLowerCase();
  const family = isIP(address);
  if (family === 4) return address;
  if (family !== 6) {
    throw new RangeError('The IP value is not an IP address.');
  }
  // The URL parser writes IPv6 in its one canonical compressed form.
  const canonical = new URL(`http://[${address}]/`).hostname.slice(1, -1);
  const mapped = /^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/.exec(canonical);
  if (mapped) {
    const high = parseInt(mapped[1], 16);
    const low = parseInt(mapped[2], 16);
    return [high >> 8, high & 0xff, low >> 8, low & 0xff].join('.');
  }
  return canonical;
}

/**
 * Peppers from config — "v2:<secret>,v1:<older>", newest first — or null when
 * unset. Throws on a malformed value (naming the entry, never its secret):
 * a broken pepper list is a configuration error, not "hashing off".
 * Generate a secret with:
 *
 *   node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
 */
export function parseIdentifierPeppers(
  raw: string | undefined,
  envName: string,
): IdentifierPepper[] | null {
  const trimmed = raw?.trim();
  if (!trimmed) return null;
  const peppers = trimmed.split(',').map((entry, index) => {
    const separator = entry.indexOf(':');
    const version = entry.slice(0, separator).trim();
    const secret = entry.slice(separator + 1).trim();
    if (separator < 0 || !VERSION.test(version)) {
      throw new Error(
        `${envName} entry ${index + 1} must look like "v1:<secret>".`,
      );
    }
    return { version, secret: Buffer.from(secret, 'utf8') };
  });
  try {
    // The constructor's checks (length, repeats) with the env name attached.
    new IdentifierHasher(peppers);
  } catch (error) {
    throw new Error(`${envName}: ${(error as Error).message}`);
  }
  return peppers;
}
