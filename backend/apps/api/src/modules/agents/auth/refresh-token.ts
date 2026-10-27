/**
 * Agent refresh tokens: generation, storage hash, and the accept/refuse rule.
 *
 * Only `hashRefreshToken(token, pepper)` is ever stored. The pepper is a
 * secret supplied by the caller (from configuration), never a constant here.
 */
import { createHmac, randomBytes as cryptoRandomBytes } from 'crypto';
import { agentCapabilitiesFor } from '../agent/agent-status';

const TOKEN_BYTES = 32;

/** Returns `n` random bytes. Injectable so tests are deterministic. */
export type RandomBytes = (n: number) => Buffer;

/** 32 random bytes as base64url (43 characters, A-Z a-z 0-9 - _). */
export function generateRefreshToken(
  randomBytes: RandomBytes = cryptoRandomBytes,
): string {
  const bytes = randomBytes(TOKEN_BYTES);
  if (!Buffer.isBuffer(bytes) || bytes.length !== TOKEN_BYTES) {
    throw new RangeError(`randomBytes must return ${TOKEN_BYTES} bytes.`);
  }
  return bytes.toString('base64url');
}

/** HMAC-SHA256 of the token, keyed with the pepper, as lower-case hex. */
export function hashRefreshToken(token: string, pepper: string): string {
  if (typeof token !== 'string' || token.length === 0) {
    throw new RangeError('token must be a non-empty string.');
  }
  if (typeof pepper !== 'string' || pepper.length === 0) {
    throw new RangeError('pepper must be a non-empty string.');
  }
  return createHmac('sha256', pepper).update(token).digest('hex');
}

export type RefreshTokenRejectReason =
  'NOT_FOUND' | 'REUSED_REVOKED_TOKEN' | 'EXPIRED' | 'AGENT_NOT_ALLOWED';

export interface RefreshTokenInput {
  /** A row with this token hash exists. */
  found: boolean;
  revokedAt: Date | null;
  expiresAt: Date;
  now: Date;
  agentStatus: string;
}

export type RefreshTokenDecision =
  { ok: true } | { ok: false; reason: RefreshTokenRejectReason };

const isValidDate = (value: Date): boolean =>
  value instanceof Date && !Number.isNaN(value.getTime());

export function decideRefreshToken(
  input: RefreshTokenInput,
): RefreshTokenDecision {
  if (!isValidDate(input.now)) {
    throw new RangeError('now must be a valid date.');
  }
  if (!input.found) return { ok: false, reason: 'NOT_FOUND' };

  // The row's own dates only mean something once the row was found.
  if (!isValidDate(input.expiresAt)) {
    throw new RangeError('expiresAt must be a valid date.');
  }
  if (input.revokedAt !== null && !isValidDate(input.revokedAt)) {
    throw new RangeError('revokedAt must be null or a valid date.');
  }

  // A revoked token presented again means it was copied or replayed: the
  // caller must revoke EVERY refresh token of this agent, not just refuse.
  if (input.revokedAt !== null) {
    return { ok: false, reason: 'REUSED_REVOKED_TOKEN' };
  }
  if (input.now.getTime() >= input.expiresAt.getTime()) {
    return { ok: false, reason: 'EXPIRED' };
  }

  // Follows docs/agent-program/agent-api.openapi.yaml ("Agent account states"):
  // every agent status may refresh. PENDING_APPROVAL and REJECTED see their
  // status, SUSPENDED reads, TERMINATED signs in read-only. Only a status the
  // contract does not know is refused.
  if (!agentCapabilitiesFor(input.agentStatus).refreshSession) {
    return { ok: false, reason: 'AGENT_NOT_ALLOWED' };
  }
  return { ok: true };
}
