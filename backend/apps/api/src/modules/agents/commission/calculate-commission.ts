/**
 * The single place a commission amount is computed. Pure: no I/O, no clock,
 * no settings lookup — callers pass the rule (snapshotted onto the commission
 * row), the commission base and the amount actually paid.
 *
 * Amounts are integers in paise. `PERCENTAGE` values are basis points
 * (1000 = 10%), so no floating point is involved. The percentage is taken of
 * `basePaise`, which may be lower than what the member paid (e.g. excluding
 * GST), and the result is capped at `amountPaidPaise` (what the member paid, GST included). New calculation types
 * are added here as another `case`; anything unrecognised throws rather than
 * silently paying zero or a guessed amount.
 */
export type CommissionCalcType = 'PERCENTAGE';

export interface CommissionRule {
  calcType: CommissionCalcType;
  /** Basis points for PERCENTAGE. */
  value: number;
}

const BASIS_POINTS_PER_UNIT = 10_000;

export function calculateCommission(
  rule: CommissionRule,
  basePaise: number,
  amountPaidPaise: number,
): number {
  if (!Number.isSafeInteger(basePaise) || basePaise < 0) {
    throw new RangeError('basePaise must be a non-negative integer.');
  }
  if (!Number.isSafeInteger(amountPaidPaise) || amountPaidPaise < 0) {
    throw new RangeError('amountPaidPaise must be a non-negative integer.');
  }
  if (!Number.isSafeInteger(rule.value) || rule.value < 0) {
    throw new RangeError('Commission value must be a non-negative integer.');
  }

  let commission: number;
  switch (rule.calcType) {
    case 'PERCENTAGE':
      // Round down, in integer arithmetic.
      commission = Math.floor((basePaise * rule.value) / BASIS_POINTS_PER_UNIT);
      break;
    default:
      throw new Error(
        `Unsupported commission calcType: ${String(rule.calcType)}`,
      );
  }

  // Never pay out more than the member paid.
  return Math.min(commission, amountPaidPaise);
}
