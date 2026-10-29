/**
 * The referred member's discount on their first paid plan.
 *
 * Pure: the caller decides eligibility (first paid plan, attributed or held
 * code, agent active) and supplies the settings (`referralDiscountBps`,
 * `onlyInCreditWindow`). All amounts are integers in paise.
 */

export interface ReferralDiscountInput {
  listAmountPaise: number;
  /** 0 to 10000 (500 = 5%). */
  referralDiscountBps: number;
  /** First paid plan, attributed or held code, agent active. */
  referralEligible: boolean;
  withinCreditWindow: boolean;
  /** Setting: the discount applies only inside the credit window. */
  onlyInCreditWindow: boolean;
}

export interface ReferralDiscount {
  discountPaise: number;
  source: 'REFERRAL_FIRST_PLAN' | 'NONE';
  taxableAfterDiscountPaise: number;
}

const BASIS_POINTS_PER_UNIT = 10_000;

export function computeReferralDiscount(
  input: ReferralDiscountInput,
): ReferralDiscount {
  if (
    !Number.isSafeInteger(input.listAmountPaise) ||
    input.listAmountPaise < 0
  ) {
    throw new RangeError('listAmountPaise must be a non-negative integer.');
  }
  if (
    !Number.isSafeInteger(input.referralDiscountBps) ||
    input.referralDiscountBps < 0 ||
    input.referralDiscountBps > BASIS_POINTS_PER_UNIT
  ) {
    throw new RangeError(
      'referralDiscountBps must be an integer from 0 to 10000.',
    );
  }

  const applies =
    input.referralEligible &&
    (input.withinCreditWindow || !input.onlyInCreditWindow);

  const discountPaise = applies
    ? Math.min(
        // Exact for any safe-integer amount.
        Number(
          (BigInt(input.listAmountPaise) * BigInt(input.referralDiscountBps)) /
            BigInt(BASIS_POINTS_PER_UNIT),
        ),
        input.listAmountPaise,
      )
    : 0;

  return {
    discountPaise,
    source: discountPaise > 0 ? 'REFERRAL_FIRST_PLAN' : 'NONE',
    taxableAfterDiscountPaise: input.listAmountPaise - discountPaise,
  };
}
