import { refundTaxPaise, splitInclusiveTax } from './referral-events';

describe('splitInclusiveTax', () => {
  it('takes the GST out of a GST-inclusive amount', () => {
    // ₹1,180 at 18% is ₹1,000 plus ₹180 GST.
    expect(splitInclusiveTax(118_000, 1800)).toEqual({
      taxableAmountPaise: 100_000,
      taxPaise: 18_000,
    });
  });

  it('always adds back up to the amount paid', () => {
    for (const amount of [1, 99, 100, 47_405, 94_905, 1_234_567]) {
      for (const rate of [0, 500, 1200, 1800, 2800]) {
        const { taxableAmountPaise, taxPaise } = splitInclusiveTax(
          amount,
          rate,
        );
        expect(taxableAmountPaise + taxPaise).toBe(amount);
        expect(taxPaise).toBeGreaterThanOrEqual(0);
      }
    }
  });

  it('charges no GST at rate 0', () => {
    expect(splitInclusiveTax(99_900, 0)).toEqual({
      taxableAmountPaise: 99_900,
      taxPaise: 0,
    });
  });

  it.each([
    [-1, 1800],
    [1.5, 1800],
    [100, -1],
    [100, 18.5],
  ])('refuses amount %p at rate %p', (amount, rate) => {
    expect(() => splitInclusiveTax(amount, rate)).toThrow(RangeError);
  });
});

describe('refundTaxPaise', () => {
  const payment = { amountPaidPaise: 94_905, taxPaise: 14_477 };

  it('is the whole GST on a full refund', () => {
    expect(
      refundTaxPaise({
        ...payment,
        refundedBeforePaise: 0,
        refundedPaise: 94_905,
      }),
    ).toBe(14_477);
  });

  it('adds up to exactly the GST however the refund is split', () => {
    const pieces = [1, 333, 10_000, 40_000, 44_571];
    let before = 0;
    let tax = 0;
    for (const piece of pieces) {
      tax += refundTaxPaise({
        ...payment,
        refundedBeforePaise: before,
        refundedPaise: piece,
      });
      before += piece;
    }
    expect(before).toBe(payment.amountPaidPaise);
    expect(tax).toBe(payment.taxPaise);
  });

  it('refuses refunds beyond what was paid', () => {
    expect(() =>
      refundTaxPaise({
        ...payment,
        refundedBeforePaise: 90_000,
        refundedPaise: 5_000,
      }),
    ).toThrow(RangeError);
  });

  it('is 0 for a free payment', () => {
    expect(
      refundTaxPaise({
        amountPaidPaise: 0,
        taxPaise: 0,
        refundedBeforePaise: 0,
        refundedPaise: 0,
      }),
    ).toBe(0);
  });
});
