import type { ReferralQuoteResult } from '@app/common';
import { parseGstRateBps, priceCheckout, PricingError } from './pricing';

const quote = (q: Partial<ReferralQuoteResult>): ReferralQuoteResult => ({
  discountPaise: 0,
  discountSource: 'NONE',
  taxableAfterDiscountPaise: 100_000,
  ...q,
});

describe('priceCheckout', () => {
  it('charges the list price with no quote and no GST', () => {
    expect(priceCheckout(399_900, null, 0)).toEqual({
      listAmountPaise: 399_900,
      discountPaise: 0,
      discountSource: 'NONE',
      heldReferralCodeId: null,
      taxableAmountPaise: 399_900,
      taxRateBps: 0,
      taxPaise: 0,
      totalPaise: 399_900,
    });
  });

  it('takes the referral discount off, then adds GST on top (Raja’s example)', () => {
    const priced = priceCheckout(
      100_000,
      quote({
        discountPaise: 5_000,
        discountSource: 'REFERRAL_FIRST_PLAN',
        taxableAfterDiscountPaise: 95_000,
        heldReferralCodeId: 'code-1',
      }),
      1800,
    );
    expect(priced).toMatchObject({
      discountPaise: 5_000,
      heldReferralCodeId: 'code-1',
      taxableAmountPaise: 95_000,
      taxPaise: 17_100,
      totalPaise: 112_100,
    });
  });

  it('holds no code when there is no discount', () => {
    expect(
      priceCheckout(100_000, quote({ heldReferralCodeId: 'code-1' }), 0)
        .heldReferralCodeId,
    ).toBeNull();
  });

  it.each([
    [
      'a discount above the price',
      { discountPaise: 100_001, discountSource: 'REFERRAL_FIRST_PLAN' },
    ],
    [
      'a negative discount',
      { discountPaise: -1, discountSource: 'REFERRAL_FIRST_PLAN' },
    ],
    ['a discount with source NONE', { discountPaise: 5_000 }],
    [
      'a referral source with no discount',
      { discountSource: 'REFERRAL_FIRST_PLAN' },
    ],
    ['an unknown source', { discountPaise: 5_000, discountSource: 'COUPON' }],
    [
      'a fractional discount',
      { discountPaise: 50.5, discountSource: 'REFERRAL_FIRST_PLAN' },
    ],
    [
      'a taxable amount that does not add up',
      {
        discountPaise: 5_000,
        discountSource: 'REFERRAL_FIRST_PLAN',
        taxableAfterDiscountPaise: 96_000,
      },
    ],
  ] as const)('refuses %s', (_label, q) => {
    const attempt = () =>
      priceCheckout(100_000, quote(q as Partial<ReferralQuoteResult>), 0);
    expect(attempt).toThrow(PricingError);
    try {
      attempt();
    } catch (error) {
      expect((error as PricingError).code).toBe('INCONSISTENT_QUOTE');
    }
  });

  it('refuses a charge below Razorpay’s minimum', () => {
    expect(() => priceCheckout(99, null, 0)).toThrow(
      new PricingError(
        'BELOW_MINIMUM_CHARGE',
        'A charge must be at least 100 paise; this one is 99.',
      ),
    );
  });
});

describe('parseGstRateBps', () => {
  it.each([
    [0, 0],
    [1800, 1800],
    [10_000, 10_000],
  ])('reads %p', (value, expected) => {
    expect(parseGstRateBps(value)).toBe(expected);
  });

  it.each([null, undefined, -1, 10_001, 18.5, '1800', true])(
    'refuses %p (no default)',
    (value) => {
      expect(parseGstRateBps(value)).toBeNull();
    },
  );
});
