/**
 * Ports for pieces another developer owns (Shaaz): OTP, platform settings,
 * identifier hashing, permissions and audit.
 *
 * The agent-program services depend only on these interfaces. Real adapters
 * are added when those pieces exist; until then the in-memory fakes in
 * `../testing/` stand in. The shapes below are the SUGGESTED contract and
 * must be confirmed with the owner before an adapter is written.
 */

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

/**
 * Contract: a challenge can be verified successfully once; a wrong code never
 * reveals the right one; after the attempt limit the challenge is dead even
 * for the right code; an expired challenge never verifies.
 */
export interface AgentOtpPort {
  send(purpose: AgentOtpPurpose, phoneE164: string): Promise<AgentOtpChallenge>;
  verify(challengeId: string, code: string): Promise<AgentOtpVerifyResult>;
}

// --- Platform settings ----------------------------------------------------

/**
 * Reads raw setting values by key. The result holds ONLY keys that are both
 * requested and set (it never returns other keys and never invents a value),
 * so it can go straight into `parseAgentProgramSettings`.
 */
export interface AgentSettingsPort {
  getMany(keys: readonly string[]): Promise<Record<string, unknown>>;
}

// --- Identifier hashing ---------------------------------------------------

export type AgentIdentifierKind = 'PHONE' | 'EMAIL' | 'PAN';

/**
 * Contract: deterministic for the same (kind, value); different for a
 * different kind or value; the output never contains the input; an empty
 * value is refused with a RangeError.
 */
export interface AgentIdentifierHasher {
  hash(kind: AgentIdentifierKind, value: string): string;
}

// --- Permissions ----------------------------------------------------------

/** Same `{ module, action }` format as `AdminAccount.permissions`. */
export interface AgentPermission {
  module: string;
  action: string;
}

export class AgentPermissionDeniedError extends Error {
  constructor(permission: AgentPermission) {
    super(`Not permitted: requires ${permission.module}.${permission.action}.`);
    this.name = 'AgentPermissionDeniedError';
  }
}

/**
 * Resolves silently when the actor holds the permission, otherwise rejects
 * with `AgentPermissionDeniedError`. An empty actor id is always denied.
 */
export interface AgentPermissionPort {
  assert(actorId: string, permission: AgentPermission): Promise<void>;
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

/** Contract: `action` and `entity` must be non-empty (RangeError otherwise). */
export interface AgentAuditPort {
  record(entry: AgentAuditEntry): Promise<void>;
}
