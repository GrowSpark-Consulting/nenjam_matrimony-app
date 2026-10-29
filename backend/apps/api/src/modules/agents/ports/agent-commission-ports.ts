/**
 * Domain-shaped repository ports for commissions, the agent ledger and
 * payouts (tables from migration 20261029110000_agent_commission_tables).
 *
 * Like `agent-data-ports.ts`, these are not Prisma shapes. Every method takes
 * an optional `tx` (see `AgentUnitOfWork`); money is integer PAISE.
 *
 * Uniqueness rules mirror the database and every violation is reported as
 * `AgentConflictError`. "Conditional" writes (`transition`, `markPaid`,
 * `cancel`, `attachToPayout`) change a row only if it is still in the state
 * the caller expects, so two requests racing for the same row cannot both
 * win; the loser gets `null` / a smaller count and must not carry on.
 */
import type { LedgerEntry } from '../commission/ledger-entries';
import type { AgentTx } from './agent-unit-of-work.port';

// --- Commission policy versions --------------------------------------------

export interface CommissionPolicyVersionRecord {
  id: string;
  version: number;
  calcType: 'PERCENTAGE';
  /** Basis points for PERCENTAGE. */
  value: number;
  holdDays: number;
  effectiveFrom: Date;
}

export interface CommissionPolicyRepository {
  findById(
    id: string,
    tx?: AgentTx,
  ): Promise<CommissionPolicyVersionRecord | null>;
  /** The newest version whose `effectiveFrom` is not after `at`, or null. */
  findActive(
    at: Date,
    tx?: AgentTx,
  ): Promise<CommissionPolicyVersionRecord | null>;
  /** The agent's own policy when one is assigned, otherwise the active one. */
  findForAgent(
    agentId: string,
    at: Date,
    tx?: AgentTx,
  ): Promise<CommissionPolicyVersionRecord | null>;
  /** Assigns (or, with null, clears) an agent's own policy. */
  assignToAgent(
    agentId: string,
    policyId: string | null,
    tx?: AgentTx,
  ): Promise<void>;
}

// --- Commissions ------------------------------------------------------------

export type CommissionStatusValue =
  | 'ON_HOLD'
  | 'AWAITING_VERIFICATION'
  | 'IN_REVIEW'
  | 'FROZEN'
  | 'READY'
  | 'APPROVED'
  | 'PAID'
  | 'CANCELLED'
  | 'REVERSED';

/** The statuses the daily approval job looks at. */
export const OPEN_COMMISSION_STATUSES: readonly CommissionStatusValue[] = [
  'ON_HOLD',
  'AWAITING_VERIFICATION',
  'IN_REVIEW',
  'FROZEN',
  'READY',
];

export interface CommissionRecord {
  id: string;
  agentId: string;
  attributionId: string;
  /** `payment_transactions.id`. The idempotency key of the payment event. */
  paymentId: string;
  /** Hash of the referred member's phone; one commission per phone, ever. */
  phoneHash: string;
  policyVersionId: string;
  status: CommissionStatusValue;
  /** The rule this commission was calculated with, snapshotted. */
  calcType: 'PERCENTAGE';
  ruleValue: number;
  /** What the percentage was taken of; null while commission.base is not set. */
  basePaise: number | null;
  /** Null until the base is known. Between 0 and `amountPaidPaise` (GST included). */
  amountPaise: number | null;
  /** What the member paid, GST INCLUDED (taxable amount + GST; prices are exclusive of GST). */
  amountPaidPaise: number;
  /** The taxable amount (list price minus the discount, before GST), as stored on the payment. */
  taxableAmountPaise: number;
  /** What has been credited to the agent's ledger for this commission. */
  creditedPaise: number;
  /** What refunds have clawed back so far. */
  reversedPaise: number;
  holdUntil: Date;
  /** Why it is IN_REVIEW (PAID_BY_AGENT, PAYMENT_SOURCE_REUSED, SELF_MATCH). */
  reviewReasons: string[];
  approvedAt: Date | null;
  paidAt: Date | null;
  cancelledAt: Date | null;
  payoutId: string | null;
  createdAt: Date;
}

export type CommissionChanges = Partial<
  Pick<
    CommissionRecord,
    | 'status'
    | 'basePaise'
    | 'amountPaise'
    | 'creditedPaise'
    | 'reversedPaise'
    | 'reviewReasons'
    | 'approvedAt'
    | 'paidAt'
    | 'cancelledAt'
  >
>;

export interface CommissionListFilter {
  agentId?: string;
  status?: CommissionStatusValue;
}

/** Position in the newest-first order: (createdAt, id), both descending. */
export interface CommissionPageCursor {
  at: Date;
  id: string;
}

export interface CommissionRepository {
  /**
   * Throws AgentConflictError DUPLICATE_COMMISSION when the attribution, the
   * payment or the phone hash already has a commission, DUPLICATE_ID for a
   * reused id.
   */
  create(commission: CommissionRecord, tx?: AgentTx): Promise<CommissionRecord>;
  findById(id: string, tx?: AgentTx): Promise<CommissionRecord | null>;
  findByPaymentId(
    paymentId: string,
    tx?: AgentTx,
  ): Promise<CommissionRecord | null>;
  findByAttributionId(
    attributionId: string,
    tx?: AgentTx,
  ): Promise<CommissionRecord | null>;
  /** Rejects when the commission does not exist. */
  update(
    id: string,
    changes: CommissionChanges,
    tx?: AgentTx,
  ): Promise<CommissionRecord>;
  /**
   * Applies `changes` only if the commission is still in `from`. Returns the
   * updated record, or null when it was in another state (a lost race) or
   * does not exist.
   */
  transition(
    id: string,
    from: CommissionStatusValue,
    changes: CommissionChanges,
    tx?: AgentTx,
  ): Promise<CommissionRecord | null>;
  /**
   * Open commissions (see `OPEN_COMMISSION_STATUSES`) in id order, at most
   * `limit`, strictly after `afterId`. For the daily approval job.
   */
  listOpen(
    page: { limit: number; afterId?: string },
    tx?: AgentTx,
  ): Promise<CommissionRecord[]>;
  /** APPROVED, not in any payout yet, oldest first. For planning a payout. */
  listPayableByAgent(
    agentId: string,
    tx?: AgentTx,
  ): Promise<CommissionRecord[]>;
  listByPayout(payoutId: string, tx?: AgentTx): Promise<CommissionRecord[]>;
  /** Newest first, ordered by (createdAt, id) descending. */
  listPage(
    filter: CommissionListFilter,
    page: { limit: number; after?: CommissionPageCursor },
    tx?: AgentTx,
  ): Promise<CommissionRecord[]>;
  /**
   * Puts the APPROVED, unattached commissions among `commissionIds` into the
   * payout. Returns how many were attached; the caller compares it with
   * `commissionIds.length` and rolls back on a difference.
   */
  attachToPayout(
    commissionIds: readonly string[],
    payoutId: string,
    tx?: AgentTx,
  ): Promise<number>;
  /** Takes every commission out of a cancelled payout. Returns how many. */
  releaseFromPayout(payoutId: string, tx?: AgentTx): Promise<number>;
  /**
   * Marks the APPROVED commissions of a payout PAID at `at`. Returns how many.
   */
  markPaidForPayout(payoutId: string, at: Date, tx?: AgentTx): Promise<number>;
}

// --- Agent ledger (append-only) ---------------------------------------------

export interface StoredLedgerEntry extends LedgerEntry {
  id: string;
  createdAt: Date;
}

export interface AgentLedgerRepository {
  /**
   * Appends the entry. The same idempotency key again appends nothing and
   * answers `{ inserted: false }`: replaying an event is safe. It never
   * throws for a repeated key, so it cannot abort an open transaction.
   */
  append(entry: LedgerEntry, tx?: AgentTx): Promise<{ inserted: boolean }>;
  findByKey(
    idempotencyKey: string,
    tx?: AgentTx,
  ): Promise<StoredLedgerEntry | null>;
  /** The sum of the agent's signed entries. May be negative. */
  balance(agentId: string, tx?: AgentTx): Promise<number>;
  /** Oldest first. */
  listByAgent(agentId: string, tx?: AgentTx): Promise<StoredLedgerEntry[]>;
}

// --- Payouts ----------------------------------------------------------------

export type AgentPayoutStatusValue = 'CREATED' | 'PAID' | 'CANCELLED';

export interface AgentPayoutRecord {
  id: string;
  agentId: string;
  /** 'YYYY-MM'. */
  period: string;
  amountPaise: number;
  taxWithheldPaise: number;
  netPaise: number;
  status: AgentPayoutStatusValue;
  reference: string | null;
  paidAt: Date | null;
  cancelReason: string | null;
  cancelledAt: Date | null;
  /** The staff user id. */
  createdBy: string;
  createdAt: Date;
}

export interface AgentPayoutListFilter {
  agentId?: string;
  status?: AgentPayoutStatusValue;
  period?: string;
}

export interface AgentPayoutRepository {
  /**
   * New payouts are CREATED. Throws AgentConflictError DUPLICATE_PAYOUT when
   * the agent already has a non-cancelled payout for the period (a cancelled
   * one frees it), DUPLICATE_ID for a reused id.
   */
  create(payout: AgentPayoutRecord, tx?: AgentTx): Promise<AgentPayoutRecord>;
  findById(id: string, tx?: AgentTx): Promise<AgentPayoutRecord | null>;
  /** The non-cancelled payout of the agent for the period, if any. */
  findActiveByAgentPeriod(
    agentId: string,
    period: string,
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord | null>;
  findByReference(
    reference: string,
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord | null>;
  /**
   * CREATED -> PAID, only if the payout is still CREATED. Returns the updated
   * payout, or null when it was in another state or does not exist. Throws
   * AgentConflictError DUPLICATE_PAYOUT_REFERENCE when another payout already
   * has the reference.
   */
  markPaid(
    id: string,
    paid: { reference: string; paidAt: Date },
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord | null>;
  /** CREATED -> CANCELLED, only if still CREATED. Null otherwise. */
  cancel(
    id: string,
    cancelled: { reason: string; at: Date },
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord | null>;
  /** Newest first, ordered by (createdAt, id) descending. */
  listPage(
    filter: AgentPayoutListFilter,
    page: { limit: number; after?: { at: Date; id: string } },
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord[]>;
}
