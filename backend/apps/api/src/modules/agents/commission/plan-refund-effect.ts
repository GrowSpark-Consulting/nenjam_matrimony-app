/**
 * What a refund does to the commission earned on the refunded payment.
 *
 * Pure: the caller loads the commission and the payment totals and applies the
 * plan. All amounts are integers in paise.
 */

export type RefundCommissionStatus =
  | 'ON_HOLD'
  | 'AWAITING_VERIFICATION'
  | 'IN_REVIEW'
  | 'FROZEN'
  | 'READY'
  | 'APPROVED'
  | 'PAID'
  | 'CANCELLED'
  | 'REVERSED';

export interface RefundEffectInput {
  commissionStatus: RefundCommissionStatus;
  /** What was credited to the agent for this payment. */
  creditedPaise: number;
  /** Already reversed by earlier partial refunds. */
  alreadyReversedPaise: number;
  amountPaidPaise: number;
  /** Total refunded on the payment so far, including this refund. */
  refundedTotalPaise: number;
  isFullRefund: boolean;
  payoutStatus: 'NONE' | 'PAID';
}

export interface RefundEffectPlan {
  commissionNext: 'CANCELLED' | 'REVERSED' | 'UNCHANGED';
  reversalPaise: number;
  balanceMayGoNegative: boolean;
}

const BEFORE_APPROVAL = new Set<RefundCommissionStatus>([
  'ON_HOLD',
  'AWAITING_VERIFICATION',
  'IN_REVIEW',
  'FROZEN',
  'READY',
]);

function assertPaise(name: string, value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${name} must be a non-negative integer.`);
  }
}

export function planRefundEffect(input: RefundEffectInput): RefundEffectPlan {
  assertPaise('creditedPaise', input.creditedPaise);
  assertPaise('alreadyReversedPaise', input.alreadyReversedPaise);
  assertPaise('amountPaidPaise', input.amountPaidPaise);
  assertPaise('refundedTotalPaise', input.refundedTotalPaise);
  if (input.amountPaidPaise <= 0) {
    throw new RangeError('amountPaidPaise must be greater than zero.');
  }
  if (input.refundedTotalPaise > input.amountPaidPaise) {
    throw new RangeError('refundedTotalPaise cannot exceed amountPaidPaise.');
  }

  const status = input.commissionStatus;

  // Already closed: a refund changes nothing more.
  if (status === 'CANCELLED' || status === 'REVERSED') {
    return unchanged();
  }

  // Nothing was credited yet, so there is nothing to claw back.
  //
  // PENDING DECISION (Raja): this cancels the whole commission even on a
  // PARTIAL refund. The alternative is to leave it open on a partial refund
  // and recalculate. This is the ONLY place that rule lives; change it here.
  if (BEFORE_APPROVAL.has(status)) {
    return {
      commissionNext: 'CANCELLED',
      reversalPaise: 0,
      balanceMayGoNegative: false,
    };
  }

  // APPROVED or PAID: claw back what was credited.
  const stillReversible = input.creditedPaise - input.alreadyReversedPaise;
  const target = input.isFullRefund
    ? stillReversible
    : proportionalReversal(input) - input.alreadyReversedPaise;
  const reversalPaise = Math.max(0, Math.min(target, stillReversible));

  return {
    commissionNext: 'REVERSED',
    reversalPaise,
    balanceMayGoNegative: input.payoutStatus === 'PAID' && reversalPaise > 0,
  };
}

/** floor(credited * refundedTotal / amountPaid), exact for any safe integers. */
function proportionalReversal(input: RefundEffectInput): number {
  return Number(
    (BigInt(input.creditedPaise) * BigInt(input.refundedTotalPaise)) /
      BigInt(input.amountPaidPaise),
  );
}

function unchanged(): RefundEffectPlan {
  return {
    commissionNext: 'UNCHANGED',
    reversalPaise: 0,
    balanceMayGoNegative: false,
  };
}
