import { isIP } from 'node:net';

/**
 * True when `key` is, or ends in, a raw IP address ("1.2.3.4", "::1",
 * "requester:1.2.3.4"). The attempt counters must be keyed by an opaque,
 * already-hashed value, never by an IP address: an IP is personal data.
 */
export function looksLikeRawIp(key: string): boolean {
  if (isIP(key) !== 0) return true;
  // A short namespace prefix such as "requester:" in front of the address.
  return isIP(key.replace(/^[a-z]+:/i, '')) !== 0;
}
