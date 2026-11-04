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
  /**
   * BEFORE approval: the commission amount before any refund reduced it, or
   * null while the amount is not known (no commission base yet). Defaults to
   * null. AFTER approval: set only when a refund reduced the commission
   * before it was approved, see `preRefundAmountPaise` on the commission.
   */
  originalAmountPaise?: number | null;
  /**
   * BEFORE approval: the running refund total already applied to the amount
   * (0 if none). It makes a replayed refund a no-op. Defaults to 0.
   */
  alreadyRefundedPaise?: number;
}

export interface RefundEffectPlan {
  /**
   * UNCHANGED also covers a partial reversal of an APPROVED / PAID commission:
   * the status stays, and the caller writes a reversal entry for
   * `reversalPaise`.
   */
  commissionNext: 'CANCELLED' | 'REVERSED' | 'REDUCED' | 'UNCHANGED';
  reversalPaise: number;
  balanceMayGoNegative: boolean;
  /**
   * Only with REDUCED (a partial refund BEFORE approval): the refund total to
   * record on the commission, and its new amount (null while the amount is
   * still unknown: the late fill then applies the same fraction). The ledger
   * is not touched, nothing was credited yet.
   */
  refundedPaise?: number;
  reducedAmountPaise?: number | null;
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
  // DECIDED (Ishu, 29 Oct): a FULL refund cancels the commission; a PARTIAL
  // refund REDUCES it in proportion to what is still paid:
  //   new amount = floor(original * (amountPaid - refundedTotal) / amountPaid)
  // using the running total, so refunds in pieces end where one refund would.
  // The status, rule snapshot and review reasons stay; the ledger is not
  // touched. This is the ONLY place that rule lives; change it here.
  if (BEFORE_APPROVAL.has(status)) {
    if (
      input.isFullRefund ||
      input.refundedTotalPaise === input.amountPaidPaise
    ) {
      return {
        commissionNext: 'CANCELLED',
        reversalPaise: 0,
        balanceMayGoNegative: false,
      };
    }
    const alreadyRefunded = input.alreadyRefundedPaise ?? 0;
    assertPaise('alreadyRefundedPaise', alreadyRefunded);
    // Totals only grow: this refund (or an older one) was already applied.
    if (input.refundedTotalPaise <= alreadyRefunded) return unchanged();
    const original = input.originalAmountPaise ?? null;
    if (original !== null) assertPaise('originalAmountPaise', original);
    return {
      commissionNext: 'REDUCED',
      reversalPaise: 0,
      balanceMayGoNegative: false,
      refundedPaise: input.refundedTotalPaise,
      reducedAmountPaise:
        original === null
          ? null
          : reduceForRefund(
              original,
              input.amountPaidPaise,
              input.refundedTotalPaise,
            ),
    };
  }

  // APPROVED or PAID. Nothing credited, nothing to claw back.
  if (input.creditedPaise === 0) return unchanged();

  // Claw back in proportion to what has been refunded so far, minus what was
  // already reversed by earlier refunds, never more than is still reversible.
  //
  // If a refund already REDUCED the commission before it was approved, the
  // credit is the reduced amount and the running total includes that earlier
  // refund, so the reduced original is the reference: what should remain is
  // floor(original * (paid - total) / paid), and only the excess is reversed.
  const original = input.originalAmountPaise ?? null;
  let target: number;
  if (input.isFullRefund) {
    target = input.creditedPaise;
  } else if (original !== null) {
    assertPaise('originalAmountPaise', original);
    const remaining = reduceForRefund(
      original,
      input.amountPaidPaise,
      input.refundedTotalPaise,
    );
    target =
      input.alreadyReversedPaise +
      (input.creditedPaise - input.alreadyReversedPaise - remaining);
  } else {
    target = proportionalReversal(input);
  }
  const reversalPaise = Math.max(
    0,
    Math.min(
      target - input.alreadyReversedPaise,
      input.creditedPaise - input.alreadyReversedPaise,
    ),
  );

  // The status only becomes REVERSED once the credit is fully reversed. Until
  // then it stays APPROVED / PAID (UNCHANGED) and the caller records a partial
  // reversal entry for `reversalPaise`.
  const fullyReversed =
    input.alreadyReversedPaise + reversalPaise >= input.creditedPaise;

  return {
    commissionNext: fullyReversed ? 'REVERSED' : 'UNCHANGED',
    reversalPaise,
    balanceMayGoNegative: input.payoutStatus === 'PAID' && reversalPaise > 0,
  };
}

/**
 * floor(original * (amountPaid - refundedTotal) / amountPaid): what is left of
 * a commission after a PARTIAL refund, exact for any safe integers (BigInt).
 */
export function reduceForRefund(
  originalAmountPaise: number,
  amountPaidPaise: number,
  refundedTotalPaise: number,
): number {
  assertPaise('originalAmountPaise', originalAmountPaise);
  assertPaise('amountPaidPaise', amountPaidPaise);
  assertPaise('refundedTotalPaise', refundedTotalPaise);
  if (amountPaidPaise <= 0) {
    throw new RangeError('amountPaidPaise must be greater than zero.');
  }
  if (refundedTotalPaise > amountPaidPaise) {
    throw new RangeError('refundedTotalPaise cannot exceed amountPaidPaise.');
  }
  return Number(
    (BigInt(originalAmountPaise) *
      BigInt(amountPaidPaise - refundedTotalPaise)) /
      BigInt(amountPaidPaise),
  );
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
