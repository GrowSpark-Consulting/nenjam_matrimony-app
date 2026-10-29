/**
 * Ports for pieces another developer owns (Shaaz): OTP, platform settings,
 * identifier hashing, permissions and audit.
 *
 * The agent-program services depend only on these interfaces. Real adapters
 * are added when those pieces exist; until then the in-memory fakes in
 * `../testing/` stand in.
 *
 * AGREED WITH SHAAZ
 * - OTP: `verify` returns the verified phone and is bound to the purpose; a
 *   challenge created for another purpose never verifies (NOT_FOUND).
 * - Hashing: HMAC-SHA256, keyed, by kind, with a version prefix ("v1:...").
 *   Callers pass RAW values; the implementation normalises per kind.
 * - Permissions: the `{ module, action }` shape, checked with an optional tx.
 * - Settings: stored JSON comes back unvalidated, so we keep validating with
 *   `parseAgentProgramSettings`.
 * - Admin and money actions write their audit row in the SAME transaction as
 *   the change (pass the tx to `AgentAuditPort.record`).
 *
 * Still to be confirmed by the real adapters: exact error mapping (see
 * `AgentPermissionDeniedError`) and rate-limit numbers.
 */
import type { AgentTx } from './agent-unit-of-work.port';

// --- OTP ------------------------------------------------------------------

export type AgentOtpPurpose = 'AGENT_SIGN_IN';

export interface AgentOtpChallenge {
  challengeId: string;
  expiresAt: Date;
}

export type AgentOtpVerifyFailure =
  | 'NOT_FOUND'
  | 'EXPIRED'
  | 'ALREADY_USED'
  | 'INVALID_CODE'
  | 'TOO_MANY_ATTEMPTS';

export type AgentOtpVerifyResult =
  | { ok: true; phoneE164: string }
  | { ok: false; reason: AgentOtpVerifyFailure };

/** `send` is asking too often for this phone and purpose. */
export class AgentOtpRateLimitError extends Error {
  constructor(public readonly retryAfterSeconds: number) {
    if (!Number.isSafeInteger(retryAfterSeconds) || retryAfterSeconds < 1) {
      throw new RangeError('retryAfterSeconds must be a positive integer.');
    }
    super(`Too many OTP requests. Retry in ${retryAfterSeconds}s.`);
    this.name = 'AgentOtpRateLimitError';
  }
}

/**
 * Contract: a challenge can be verified successfully once; it only verifies
 * for the purpose it was created for (any other purpose answers NOT_FOUND, so
 * nothing about it leaks); a wrong code never reveals the right one; after
 * the attempt limit the challenge is dead even for the right code; an expired
 * challenge never verifies. `send` may reject with `AgentOtpRateLimitError`.
 */
export interface AgentOtpPort {
  send(purpose: AgentOtpPurpose, phoneE164: string): Promise<AgentOtpChallenge>;
  verify(
    purpose: AgentOtpPurpose,
    challengeId: string,
    code: string,
  ): Promise<AgentOtpVerifyResult>;
}

// --- Platform settings ----------------------------------------------------

/**
 * Reads raw setting values by key. The result holds ONLY keys that are both
 * requested and set (it never returns other keys and never invents a value),
 * so it can go straight into `parseAgentProgramSettings`. Values are stored
 * JSON and are NOT validated here.
 */
export interface AgentSettingsPort {
  getMany(keys: readonly string[]): Promise<Record<string, unknown>>;
}

// --- Identifier hashing ---------------------------------------------------

export type AgentIdentifierKind = 'PHONE' | 'EMAIL' | 'PAN';

/**
 * Callers pass RAW values. The real implementation normalises per kind (an
 * E.164 phone, a trimmed lower-case email, an upper-case PAN) and returns a
 * version-prefixed, keyed hash such as "v1:<hex>".
 *
 * Contract: synchronous; two spellings of the same identifier give the same
 * hash; a different kind or value gives a different hash; the output never
 * contains the input; a value that is empty after trimming is refused with a
 * RangeError.
 */
export interface AgentIdentifierHasher {
  hash(kind: AgentIdentifierKind, value: string): string;
  /**
   * The hash under EVERY active pepper version, newest first (the first one
   * is `hash(kind, value)`). A stored hash may have been made under an older
   * version while IDENTIFIER_HASH_PEPPERS is being rotated, so a lookup that
   * must not miss (a duplicate check) compares against all of them. Same
   * normalisation and the same RangeError as `hash`.
   */
  hashAll(kind: AgentIdentifierKind, value: string): string[];
}

// --- Permissions ----------------------------------------------------------

/** Same `{ module, action }` format as `AdminAccount.permissions`. */
export interface AgentPermission {
  module: string;
  action: string;
}

/**
 * The only error `AgentPermissionPort.assert` rejects with. A later adapter
 * or exception filter maps it to HTTP 403: Shaaz's real check throws Nest's
 * ForbiddenException, so the real adapter converts it to this.
 */
export class AgentPermissionDeniedError extends Error {
  constructor(permission: AgentPermission) {
    super(`Not permitted: requires ${permission.module}.${permission.action}.`);
    this.name = 'AgentPermissionDeniedError';
  }
}

/**
 * Resolves silently when the actor holds the permission, otherwise rejects
 * with `AgentPermissionDeniedError`. An empty actor id is always denied.
 * Pass the `tx` when checking inside a transaction.
 */
export interface AgentPermissionPort {
  assert(
    actorId: string,
    permission: AgentPermission,
    tx?: AgentTx,
  ): Promise<void>;
}

// --- Audit ----------------------------------------------------------------

export interface AgentAuditEntry {
  actorId: string | null;
  action: string;
  entity: string;
  entityId: string | null;
  /** Never put tokens, OTPs, PAN or bank details here. */
  metadata?: Record<string, unknown>;
}

/**
 * Contract: `action` and `entity` must be non-empty (RangeError otherwise).
 * Money and admin actions MUST pass the `tx`, so the audit row commits (or
 * rolls back) together with the change it describes.
 */
export interface AgentAuditPort {
  record(entry: AgentAuditEntry, tx?: AgentTx): Promise<void>;
}
