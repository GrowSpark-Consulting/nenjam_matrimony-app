import {
  computeReferralDiscount,
  ReferralDiscountInput,
} from './compute-referral-discount';

const input = (
  overrides: Partial<ReferralDiscountInput> = {},
): ReferralDiscountInput => ({
  listAmountPaise: 99_900,
  referralDiscountBps: 500,
  referralEligible: true,
  withinCreditWindow: true,
  onlyInCreditWindow: true,
  ...overrides,
});

describe('computeReferralDiscount', () => {
  it('gives 5% off the first plan (Rs. 999.00 -> Rs. 49.95 off)', () => {
    expect(computeReferralDiscount(input())).toEqual({
      discountPaise: 4_995,
      source: 'REFERRAL_FIRST_PLAN',
      taxableAfterDiscountPaise: 94_905,
    });
  });

  it('uses the rate it is given', () => {
    expect(
      computeReferralDiscount(input({ referralDiscountBps: 1000 })),
    ).toEqual({
      discountPaise: 9_990,
      source: 'REFERRAL_FIRST_PLAN',
      taxableAfterDiscountPaise: 89_910,
    });
  });

  describe('eligibility and the credit window', () => {
    const NONE = {
      discountPaise: 0,
      source: 'NONE',
      taxableAfterDiscountPaise: 99_900,
    };

    it.each([
      // referralEligible, withinCreditWindow, onlyInCreditWindow, applies
      [true, true, true, true],
      [true, true, false, true],
      [true, false, false, true],
      [true, false, true, false],
      [false, true, true, false],
      [false, true, false, false],
      [false, false, false, false],
      [false, false, true, false],
    ])(
      'eligible=%p, inWindow=%p, onlyInWindow=%p -> applies=%p',
      (referralEligible, withinCreditWindow, onlyInCreditWindow, applies) => {
        const result = computeReferralDiscount(
          input({ referralEligible, withinCreditWindow, onlyInCreditWindow }),
        );
        if (applies) {
          expect(result).toEqual({
            discountPaise: 4_995,
            source: 'REFERRAL_FIRST_PLAN',
            taxableAfterDiscountPaise: 94_905,
          });
        } else {
          expect(result).toEqual(NONE);
        }
      },
    );
  });

  describe('rounding', () => {
    it('rounds the discount down', () => {
      // 5% of 999 paise = 49.95 -> 49
      expect(computeReferralDiscount(input({ listAmountPaise: 999 }))).toEqual({
        discountPaise: 49,
        source: 'REFERRAL_FIRST_PLAN',
        taxableAfterDiscountPaise: 950,
      });
    });

    it('a discount that rounds to zero is NONE', () => {
      // 5% of 19 paise = 0.95 -> 0
      expect(computeReferralDiscount(input({ listAmountPaise: 19 }))).toEqual({
        discountPaise: 0,
        source: 'NONE',
        taxableAfterDiscountPaise: 19,
      });
    });
  });

  describe('caps and edges', () => {
    it('a 100% rate makes the plan free and never goes below zero', () => {
      expect(
        computeReferralDiscount(input({ referralDiscountBps: 10_000 })),
      ).toEqual({
        discountPaise: 99_900,
        source: 'REFERRAL_FIRST_PLAN',
        taxableAfterDiscountPaise: 0,
      });
    });

    it('a 0% rate gives NONE', () => {
      expect(
        computeReferralDiscount(input({ referralDiscountBps: 0 })),
      ).toEqual({
        discountPaise: 0,
        source: 'NONE',
        taxableAfterDiscountPaise: 99_900,
      });
    });

    it('a zero list amount gives NONE', () => {
      expect(computeReferralDiscount(input({ listAmountPaise: 0 }))).toEqual({
        discountPaise: 0,
        source: 'NONE',
        taxableAfterDiscountPaise: 0,
      });
    });

    it('is exact for very large amounts', () => {
      const result = computeReferralDiscount(
        input({
          listAmountPaise: 9_007_199_254_740_991,
          referralDiscountBps: 9_999,
        }),
      );
      expect(result.discountPaise).toBe(9_006_298_534_815_516);
      expect(result.taxableAfterDiscountPaise + result.discountPaise).toBe(
        9_007_199_254_740_991,
      );
    });

    it('discount + amount paid always equals the list amount', () => {
      for (const listAmountPaise of [1, 7, 333, 12_345, 99_999]) {
        for (const referralDiscountBps of [0, 1, 500, 3_333, 10_000]) {
          const r = computeReferralDiscount(
            input({ listAmountPaise, referralDiscountBps }),
          );
          expect(r.discountPaise + r.taxableAfterDiscountPaise).toBe(
            listAmountPaise,
          );
          expect(r.discountPaise).toBeLessThanOrEqual(listAmountPaise);
          expect(r.taxableAfterDiscountPaise).toBeGreaterThanOrEqual(0);
        }
      }
    });
  });

  describe('validation', () => {
    it.each([-1, 1.5, NaN, Infinity])('rejects listAmountPaise %p', (value) => {
      expect(() =>
        computeReferralDiscount(input({ listAmountPaise: value })),
      ).toThrow(RangeError);
    });

    it.each([-1, 10_001, 2.5, NaN, Infinity])(
      'rejects referralDiscountBps %p',
      (value) => {
        expect(() =>
          computeReferralDiscount(input({ referralDiscountBps: value })),
        ).toThrow(RangeError);
      },
    );

    it('validates even when the discount does not apply', () => {
      expect(() =>
        computeReferralDiscount(
          input({ referralEligible: false, referralDiscountBps: -1 }),
        ),
      ).toThrow(RangeError);
    });
  });
});
