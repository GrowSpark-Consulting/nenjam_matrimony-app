/**
 * Builders for the agent commission ledger, and its balance.
 *
 * Every money movement is one signed entry; the balance is their sum. The
 * typed builders take a POSITIVE magnitude and apply the sign themselves, so a
 * caller cannot credit by accident when it meant to debit. Each entry carries
 * an idempotency key, so replaying the same event (a webhook retried, a job
 * re-run) can never write it twice. All amounts are integers in paise.
 */

export type LedgerEntryType =
  'CREDIT' | 'REVERSAL' | 'PAYOUT_DEBIT' | 'PAYOUT_RELEASE' | 'ADJUSTMENT';

export interface LedgerEntry {
  agentId: string;
  type: LedgerEntryType;
  /** Signed: + adds to the agent's balance, - takes from it. */
  amountPaise: number;
  idempotencyKey: string;
  commissionId: string | null;
  refundId: string | null;
  payoutId: string | null;
  /** The commission rule, snapshotted on CREDIT entries only. */
  calcType: string | null;
  value: number | null;
  ruleSnapshot: unknown;
  /** Required on ADJUSTMENT entries. */
  reason: string | null;
}

const EMPTY_LINKS = {
  commissionId: null,
  refundId: null,
  payoutId: null,
  calcType: null,
  value: null,
  ruleSnapshot: null,
  reason: null,
} as const;

function assertId(name: string, value: unknown): asserts value is string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new RangeError(`${name} must be a non-empty string.`);
  }
}

function assertPositive(name: string, value: number): void {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new RangeError(`${name} must be a positive integer.`);
  }
}

export interface CreditEntryInput {
  agentId: string;
  commissionId: string;
  amountPaise: number;
  calcType: string;
  value: number;
  ruleSnapshot: unknown;
}

/** A commission credited to the agent (+). */
export function buildCreditEntry(input: CreditEntryInput): LedgerEntry {
  assertId('agentId', input.agentId);
  assertId('commissionId', input.commissionId);
  assertPositive('amountPaise', input.amountPaise);
  assertId('calcType', input.calcType);
  if (!Number.isSafeInteger(input.value) || input.value < 0) {
    throw new RangeError('value must be a non-negative integer.');
  }
  return {
    ...EMPTY_LINKS,
    agentId: input.agentId,
    type: 'CREDIT',
    amountPaise: input.amountPaise,
    idempotencyKey: `credit:${input.commissionId}`,
    commissionId: input.commissionId,
    calcType: input.calcType,
    value: input.value,
    ruleSnapshot: input.ruleSnapshot ?? null,
  };
}

export interface ReversalEntryInput {
  agentId: string;
  commissionId: string;
  refundId: string;
  reversalPaise: number;
}

/** Commission clawed back after a refund (-). One entry per refund. */
export function buildReversalEntry(input: ReversalEntryInput): LedgerEntry {
  assertId('agentId', input.agentId);
  assertId('commissionId', input.commissionId);
  assertId('refundId', input.refundId);
  assertPositive('reversalPaise', input.reversalPaise);
  return {
    ...EMPTY_LINKS,
    agentId: input.agentId,
    type: 'REVERSAL',
    amountPaise: -input.reversalPaise,
    idempotencyKey: `reversal:${input.refundId}`,
    commissionId: input.commissionId,
    refundId: input.refundId,
  };
}

export interface PayoutEntryInput {
  agentId: string;
  payoutId: string;
  amountPaise: number;
}

/** Money set aside for a payout (-). */
export function buildPayoutDebitEntry(input: PayoutEntryInput): LedgerEntry {
  assertId('agentId', input.agentId);
  assertId('payoutId', input.payoutId);
  assertPositive('amountPaise', input.amountPaise);
  return {
    ...EMPTY_LINKS,
    agentId: input.agentId,
    type: 'PAYOUT_DEBIT',
    amountPaise: -input.amountPaise,
    idempotencyKey: `payout:${input.payoutId}`,
    payoutId: input.payoutId,
  };
}

/** A cancelled payout gives its money back (+). */
export function buildPayoutReleaseEntry(input: PayoutEntryInput): LedgerEntry {
  assertId('agentId', input.agentId);
  assertId('payoutId', input.payoutId);
  assertPositive('amountPaise', input.amountPaise);
  return {
    ...EMPTY_LINKS,
    agentId: input.agentId,
    type: 'PAYOUT_RELEASE',
    amountPaise: input.amountPaise,
    idempotencyKey: `payout-release:${input.payoutId}`,
    payoutId: input.payoutId,
  };
}

export interface AdjustmentEntryInput {
  agentId: string;
  /** Signed and non-zero: + or -. */
  amountPaise: number;
  reason: string;
  /** Supplied by the caller: an adjustment has no natural key. */
  idempotencyKey: string;
}

/** A manual correction (+ or -). A reason is required. */
export function buildAdjustmentEntry(input: AdjustmentEntryInput): LedgerEntry {
  assertId('agentId', input.agentId);
  if (!Number.isSafeInteger(input.amountPaise) || input.amountPaise === 0) {
    throw new RangeError('amountPaise must be a non-zero integer.');
  }
  if (typeof input.reason !== 'string' || input.reason.trim() === '') {
    throw new RangeError('An adjustment needs a reason.');
  }
  assertId('idempotencyKey', input.idempotencyKey);
  return {
    ...EMPTY_LINKS,
    agentId: input.agentId,
    type: 'ADJUSTMENT',
    amountPaise: input.amountPaise,
    idempotencyKey: input.idempotencyKey,
    reason: input.reason.trim(),
  };
}

/**
 * Sum of signed entry amounts. Added up exactly (BigInt), then returned as a
 * number; throws if any amount is not an integer or the total leaves the safe
 * integer range. May be negative (a reversal after the money was paid out).
 */
export function sumLedgerBalance(
  entries: ReadonlyArray<Pick<LedgerEntry, 'amountPaise'>>,
): number {
  let total = 0n;
  for (const entry of entries) {
    if (!Number.isSafeInteger(entry.amountPaise)) {
      throw new RangeError('Every amountPaise must be a safe integer.');
    }
    total += BigInt(entry.amountPaise);
  }
  if (
    total > BigInt(Number.MAX_SAFE_INTEGER) ||
    total < BigInt(Number.MIN_SAFE_INTEGER)
  ) {
    throw new RangeError('Ledger balance is outside the safe integer range.');
  }
  return Number(total);
}
