/**
 * Builds the commission row to create when a referred member pays.
 *
 * Pure: the caller supplies the rule snapshot, the hold length, the amounts and
 * the fraud-signal flags. Nothing here is a business default.
 */
import { calculateCommission, CommissionRule } from './calculate-commission';

export type CommissionPaidBy = 'MEMBER' | 'AGENT' | 'ADMIN_RECORDED';

export type CommissionDraftReason =
  'PAID_BY_AGENT' | 'PAYMENT_SOURCE_REUSED' | 'SELF_MATCH';

export interface CommissionDraftInput {
  rule: CommissionRule;
  holdDays: number;
  now: Date;
  amountPaidPaise: number;
  /** Null when commission.base is not configured. */
  basePaise: number | null;
  paidBy: CommissionPaidBy;
  paymentSourceReused: boolean;
  memberPhoneMatchesAgent: boolean;
}

export interface CommissionDraft {
  /** IN_REVIEW when any flag is set, otherwise ON_HOLD. */
  status: 'ON_HOLD' | 'IN_REVIEW';
  holdUntil: Date;
  /** Null when there is no base to calculate on yet. */
  amountPaise: number | null;
  /** The rule, snapshotted onto the commission. */
  calcType: CommissionRule['calcType'];
  value: number;
  reasons: CommissionDraftReason[];
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

export function buildCommissionDraft(
  input: CommissionDraftInput,
): CommissionDraft {
  if (!Number.isSafeInteger(input.holdDays) || input.holdDays < 0) {
    throw new RangeError('holdDays must be a non-negative integer.');
  }
  if (Number.isNaN(input.now.getTime())) {
    throw new RangeError('now must be a valid date.');
  }
  if (
    !Number.isSafeInteger(input.amountPaidPaise) ||
    input.amountPaidPaise < 0
  ) {
    throw new RangeError('amountPaidPaise must be a non-negative integer.');
  }

  // calculateCommission validates the rule and the base. With no base it is not
  // called for an amount, so run it on zeros purely to validate the rule.
  let amountPaise: number | null = null;
  if (input.basePaise === null) {
    calculateCommission(input.rule, 0, 0);
  } else {
    amountPaise = calculateCommission(
      input.rule,
      input.basePaise,
      input.amountPaidPaise,
    );
  }

  const reasons: CommissionDraftReason[] = [];
  if (input.paidBy === 'AGENT') reasons.push('PAID_BY_AGENT');
  if (input.paymentSourceReused) reasons.push('PAYMENT_SOURCE_REUSED');
  if (input.memberPhoneMatchesAgent) reasons.push('SELF_MATCH');

  return {
    status: reasons.length > 0 ? 'IN_REVIEW' : 'ON_HOLD',
    holdUntil: new Date(input.now.getTime() + input.holdDays * MS_PER_DAY),
    amountPaise,
    calcType: input.rule.calcType,
    value: input.rule.value,
    reasons,
  };
}
