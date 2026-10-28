/**
 * Domain-shaped repository ports and the read-only member port.
 *
 * These are NOT Prisma shapes: a Prisma adapter maps to and from them once
 * the Phase 1 tables exist (PR #116). The record fields are the minimum the
 * planned services need and may grow; none of this is final.
 *
 * Every method takes an optional `tx` (see `AgentUnitOfWork`). Writes that
 * are given it commit or roll back with the transaction; reads that must see
 * those writes pass it too.
 *
 * Uniqueness rules mirror the planned database constraints, and every
 * violation is reported as `AgentConflictError` so services handle one error
 * whether a fake or a real database enforced it.
 */
import type { AgentStatus } from '../agent/agent-status';
import type { AttributionSource } from '../referral/decide-attribution';
import type { ReferralViewSource } from '../referral/agent-referral-view';
import type { AgentTx } from './agent-unit-of-work.port';

export type AgentConflictReason =
  | 'DUPLICATE_PHONE_HASH'
  | 'DUPLICATE_CODE'
  | 'DUPLICATE_PRIMARY_CODE'
  | 'DUPLICATE_ATTRIBUTION'
  | 'ALREADY_REVOKED'
  | 'DUPLICATE_ID';

export class AgentConflictError extends Error {
  constructor(public readonly reason: AgentConflictReason) {
    super(`Conflict: ${reason}`);
    this.name = 'AgentConflictError';
  }
}

// --- Agents ----------------------------------------------------------------

export interface AgentRecord {
  id: string;
  phoneHash: string;
  phoneE164: string;
  name: string;
  city: string;
  state: string;
  status: AgentStatus;
  rejectionReason: string | null;
  approvedAt: Date | null;
  panLast4: string | null;
  /** The full PAN, sealed by `AgentSecretSealer`. Never returned to clients. */
  panSealed: string | null;
  payoutDetailsSet: boolean;
  createdAt: Date;
}

export type NewAgentRecord = Omit<
  AgentRecord,
  'status' | 'rejectionReason' | 'approvedAt' | 'payoutDetailsSet'
>;

/** `status` is stored as given; transition rules live in `agent-status.ts`. */
export interface AgentRepository {
  findById(id: string, tx?: AgentTx): Promise<AgentRecord | null>;
  findByPhoneHash(phoneHash: string, tx?: AgentTx): Promise<AgentRecord | null>;
  /** Starts as PENDING_APPROVAL. Throws AgentConflictError on a reused id or phone hash. */
  create(agent: NewAgentRecord, tx?: AgentTx): Promise<AgentRecord>;
  update(
    id: string,
    changes: Partial<
      Pick<
        AgentRecord,
        | 'name'
        | 'city'
        | 'state'
        | 'status'
        | 'rejectionReason'
        | 'approvedAt'
        | 'panLast4'
        | 'panSealed'
        | 'payoutDetailsSet'
      >
    >,
    tx?: AgentTx,
  ): Promise<AgentRecord>;
}

// --- Referral codes --------------------------------------------------------

export interface ReferralCodeRecord {
  id: string;
  agentId: string;
  /** Normalised, e.g. NM7K2P9X. */
  code: string;
  isPrimary: boolean;
  isActive: boolean;
  createdAt: Date;
}

export interface ReferralCodeRepository {
  findByCode(code: string, tx?: AgentTx): Promise<ReferralCodeRecord | null>;
  listByAgent(agentId: string, tx?: AgentTx): Promise<ReferralCodeRecord[]>;
  codeExists(code: string, tx?: AgentTx): Promise<boolean>;
  /**
   * Throws AgentConflictError DUPLICATE_CODE for a reused code, or
   * DUPLICATE_PRIMARY_CODE when the agent already has a primary code.
   */
  create(code: ReferralCodeRecord, tx?: AgentTx): Promise<ReferralCodeRecord>;
}

// --- Refresh tokens --------------------------------------------------------

export interface AgentRefreshTokenRecord {
  id: string;
  agentId: string;
  /** `hashRefreshToken(...)` only; the raw token is never stored. */
  tokenHash: string;
  expiresAt: Date;
  revokedAt: Date | null;
  createdAt: Date;
}

export interface AgentRefreshTokenRepository {
  create(
    token: AgentRefreshTokenRecord,
    tx?: AgentTx,
  ): Promise<AgentRefreshTokenRecord>;
  findByHash(
    tokenHash: string,
    tx?: AgentTx,
  ): Promise<AgentRefreshTokenRecord | null>;
  /**
   * Atomically revokes `currentId` and stores `next`. Throws AgentConflictError
   * ALREADY_REVOKED if `currentId` was already revoked (a concurrent refresh),
   * leaving nothing stored.
   */
  rotate(
    currentId: string,
    next: AgentRefreshTokenRecord,
    at: Date,
    tx?: AgentTx,
  ): Promise<AgentRefreshTokenRecord>;
  /** Revokes one token; true if it was active, false if unknown or already revoked. */
  revoke(tokenId: string, at: Date, tx?: AgentTx): Promise<boolean>;
  /** Revokes every still-active token of the agent; returns how many. */
  revokeAllForAgent(agentId: string, at: Date, tx?: AgentTx): Promise<number>;
}

// --- Applicants (verified phone, before an agent record exists) -----------

export interface AgentApplicantRecord {
  phoneHash: string;
  /** The verified E.164 phone, sealed by `AgentSecretSealer`. */
  phoneSealed: string;
  expiresAt: Date;
}

/**
 * Remembers the phone an applicant verified, so the application can create
 * the agent record without the phone being in the token or the request body.
 * Written at verify time; deleted after a successful application.
 */
export interface AgentApplicantRepository {
  /** Insert or replace the record for this phone hash. */
  save(record: AgentApplicantRecord, tx?: AgentTx): Promise<void>;
  /** Returns the record even if it has expired; the caller checks `expiresAt`. */
  find(phoneHash: string, tx?: AgentTx): Promise<AgentApplicantRecord | null>;
  delete(phoneHash: string, tx?: AgentTx): Promise<void>;
}

// --- Attribution -----------------------------------------------------------

export interface ReferralAttributionRecord {
  id: string;
  memberId: string;
  agentId: string;
  codeId: string;
  source: AttributionSource;
  /** Hash of the member's verified phone, null when there is none. */
  memberPhoneHash: string | null;
  attributedAt: Date;
}

export interface ReferralAttributionRepository {
  findByMemberId(
    memberId: string,
    tx?: AgentTx,
  ): Promise<ReferralAttributionRecord | null>;
  listByAgent(
    agentId: string,
    tx?: AgentTx,
  ): Promise<ReferralAttributionRecord[]>;
  /** True when an attribution already exists for this member phone hash. */
  isPhoneHashCredited(phoneHash: string, tx?: AgentTx): Promise<boolean>;
  /** One attribution per member: throws DUPLICATE_ATTRIBUTION otherwise. */
  create(
    attribution: ReferralAttributionRecord,
    tx?: AgentTx,
  ): Promise<ReferralAttributionRecord>;
}

// --- Members (read only) ---------------------------------------------------

export interface AgentMemberSnapshot {
  memberId: string;
  phoneHash: string | null;
  signedUpAt: Date;
  /** Any earlier successful payment. */
  hasPaid: boolean;
}

/** Read-only view of members; agent code never writes member data. */
export interface AgentMemberReadPort {
  getMember(
    memberId: string,
    tx?: AgentTx,
  ): Promise<AgentMemberSnapshot | null>;
  /** Display fields for the referrals list; null when the member is gone. */
  getReferralViewFields(
    memberId: string,
    tx?: AgentTx,
  ): Promise<Omit<
    ReferralViewSource,
    'attributionId' | 'commissionStatus'
  > | null>;
}
