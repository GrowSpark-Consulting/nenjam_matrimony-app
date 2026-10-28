/**
 * Domain-shaped repository ports and the read-only member port.
 *
 * These are NOT Prisma shapes: a Prisma adapter maps to and from them once
 * the Phase 1 tables exist (PR #116). The record fields are the minimum the
 * planned services need and may grow; none of this is final.
 *
 * Uniqueness rules mirror the planned database constraints, and every
 * violation is reported as `AgentConflictError` so services handle one error
 * whether a fake or a real database enforced it.
 */
import type { AgentStatus } from '../agent/agent-status';
import type { AttributionSource } from '../referral/decide-attribution';
import type { ReferralViewSource } from '../referral/agent-referral-view';

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
  payoutDetailsSet: boolean;
  createdAt: Date;
}

export type NewAgentRecord = Omit<
  AgentRecord,
  'status' | 'rejectionReason' | 'approvedAt' | 'payoutDetailsSet'
>;

/** `status` is stored as given; transition rules live in `agent-status.ts`. */
export interface AgentRepository {
  findById(id: string): Promise<AgentRecord | null>;
  findByPhoneHash(phoneHash: string): Promise<AgentRecord | null>;
  /** Starts as PENDING_APPROVAL. Throws AgentConflictError on a reused id or phone hash. */
  create(agent: NewAgentRecord): Promise<AgentRecord>;
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
        | 'payoutDetailsSet'
      >
    >,
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
  findByCode(code: string): Promise<ReferralCodeRecord | null>;
  listByAgent(agentId: string): Promise<ReferralCodeRecord[]>;
  codeExists(code: string): Promise<boolean>;
  /**
   * Throws AgentConflictError DUPLICATE_CODE for a reused code, or
   * DUPLICATE_PRIMARY_CODE when the agent already has a primary code.
   */
  create(code: ReferralCodeRecord): Promise<ReferralCodeRecord>;
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
  create(token: AgentRefreshTokenRecord): Promise<AgentRefreshTokenRecord>;
  findByHash(tokenHash: string): Promise<AgentRefreshTokenRecord | null>;
  /**
   * Atomically revokes `currentId` and stores `next`. Throws AgentConflictError
   * ALREADY_REVOKED if `currentId` was already revoked (a concurrent refresh),
   * leaving nothing stored.
   */
  rotate(
    currentId: string,
    next: AgentRefreshTokenRecord,
    at: Date,
  ): Promise<AgentRefreshTokenRecord>;
  /** Revokes every still-active token of the agent; returns how many. */
  revokeAllForAgent(agentId: string, at: Date): Promise<number>;
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
  findByMemberId(memberId: string): Promise<ReferralAttributionRecord | null>;
  listByAgent(agentId: string): Promise<ReferralAttributionRecord[]>;
  /** True when an attribution already exists for this member phone hash. */
  isPhoneHashCredited(phoneHash: string): Promise<boolean>;
  /** One attribution per member: throws DUPLICATE_ATTRIBUTION otherwise. */
  create(
    attribution: ReferralAttributionRecord,
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
  getMember(memberId: string): Promise<AgentMemberSnapshot | null>;
  /** Display fields for the referrals list; null when the member is gone. */
  getReferralViewFields(
    memberId: string,
  ): Promise<Omit<
    ReferralViewSource,
    'attributionId' | 'commissionStatus'
  > | null>;
}
