/**
 * Plans one manual payout for an agent and period.
 *
 * Pure: the caller loads the approved, unpaid commissions, computes
 * eligibility with decidePayoutEligibility(), and reads the tax-withholding
 * setting. Nothing here writes the payout or its ledger entries.
 */
import type { PayoutEligibility } from './decide-payout-eligibility';

export interface PayoutCommission {
  id: string;
  creditedPaise: number;
  reversedPaise: number;
}

export interface PlanPayoutInput {
  agentId: string;
  /** Calendar month, e.g. '2026-11'. */
  period: string;
  /** Approved, not yet paid. */
  commissions: ReadonlyArray<PayoutCommission>;
  /** From decidePayoutEligibility(), computed by the caller. */
  eligibility: Pick<PayoutEligibility, 'eligible' | 'reasons'>;
  /** The payout.tax_withholding setting, passed through untouched. */
  taxWithholding: unknown;
}

export interface PlannedPayout {
  agentId: string;
  period: string;
  amountPaise: number;
  taxWithheldPaise: number;
  netPaise: number;
  commissionIds: string[];
  warnings: string[];
}

export type PayoutPlan =
  { ok: true; payout: PlannedPayout } | { ok: false; reasons: string[] };

const PERIOD_PATTERN = /^\d{4}-(0[1-9]|1[0-2])$/;

export function planPayout(input: PlanPayoutInput): PayoutPlan {
  if (typeof input.agentId !== 'string' || input.agentId.trim() === '') {
    throw new RangeError('agentId must be a non-empty string.');
  }
  if (typeof input.period !== 'string' || !PERIOD_PATTERN.test(input.period)) {
    throw new RangeError("period must look like 'YYYY-MM'.");
  }

  // Validate every commission up front, whatever the outcome.
  const seen = new Set<string>();
  let total = 0n;
  for (const c of input.commissions) {
    if (typeof c.id !== 'string' || c.id.trim() === '') {
      throw new RangeError('Every commission needs a non-empty id.');
    }
    if (seen.has(c.id)) {
      // Paying the same commission twice is never right.
      throw new RangeError(`Commission ${c.id} is listed twice.`);
    }
    seen.add(c.id);
    for (const [name, value] of [
      ['creditedPaise', c.creditedPaise],
      ['reversedPaise', c.reversedPaise],
    ] as const) {
      if (!Number.isSafeInteger(value) || value < 0) {
        throw new RangeError(`${name} must be a non-negative integer.`);
      }
    }
    if (c.creditedPaise - c.reversedPaise < 0) {
      throw new RangeError(
        `Commission ${c.id} has more reversed than credited.`,
      );
    }
    total += BigInt(c.creditedPaise - c.reversedPaise);
  }
  if (total > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new RangeError('Payout amount is outside the safe integer range.');
  }
  const amountPaise = Number(total);

  if (!input.eligibility.eligible) {
    return { ok: false, reasons: [...input.eligibility.reasons] };
  }

  const reasons: string[] = [];
  if (input.commissions.length === 0 || amountPaise <= 0) {
    reasons.push('NOTHING_TO_PAY');
  }
  // The shape of a tax-withholding rule is waiting on the CA, so any value
  // other than "not set" cannot be applied yet.
  const taxRuleSet =
    input.taxWithholding !== null && input.taxWithholding !== undefined;
  if (taxRuleSet) reasons.push('TAX_RULE_UNSUPPORTED');
  if (reasons.length > 0) return { ok: false, reasons };

  const taxWithheldPaise = 0;
  return {
    ok: true,
    payout: {
      agentId: input.agentId,
      period: input.period,
      amountPaise,
      taxWithheldPaise,
      netPaise: amountPaise - taxWithheldPaise,
      commissionIds: input.commissions.map((c) => c.id),
      warnings: ['TAX_RULE_NOT_SET'],
    },
  };
}
