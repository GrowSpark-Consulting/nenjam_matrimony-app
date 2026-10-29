import { addExclusiveTax, refundTaxPaise } from './referral-events';

describe('addExclusiveTax', () => {
  it('adds GST on top of the taxable amount (Raja’s example)', () => {
    // ₹1,000 with 5% off is ₹950 taxable; 18% GST is ₹171; ₹1,121 paid.
    expect(addExclusiveTax(95_000, 1800)).toEqual({
      taxPaise: 17_100,
      totalPaise: 112_100,
    });
  });

  it('adds nothing at rate 0 (not GST-registered yet)', () => {
    expect(addExclusiveTax(95_000, 0)).toEqual({
      taxPaise: 0,
      totalPaise: 95_000,
    });
  });

  it('rounds the GST to the nearest paisa, half up', () => {
    expect(addExclusiveTax(99, 1800).taxPaise).toBe(18); // 17.82
    expect(addExclusiveTax(25, 1800).taxPaise).toBe(5); // 4.5
    expect(addExclusiveTax(24, 1800).taxPaise).toBe(4); // 4.32
  });

  it('always totals taxable + tax', () => {
    for (const taxable of [0, 1, 99, 100, 47_405, 94_905, 1_234_567]) {
      for (const rate of [0, 500, 1200, 1800, 2800]) {
        const { taxPaise, totalPaise } = addExclusiveTax(taxable, rate);
        expect(totalPaise).toBe(taxable + taxPaise);
        expect(taxPaise).toBeGreaterThanOrEqual(0);
      }
    }
  });

  it.each([
    [-1, 1800],
    [1.5, 1800],
    [100, -1],
    [100, 18.5],
  ])('refuses taxable %p at rate %p', (taxable, rate) => {
    expect(() => addExclusiveTax(taxable, rate)).toThrow(RangeError);
  });
});

describe('refundTaxPaise', () => {
  // Raja's example: 112100 paid, of which 17100 GST.
  const payment = { amountPaidPaise: 112_100, taxPaise: 17_100 };

  it('is the whole GST on a full refund', () => {
    expect(
      refundTaxPaise({
        ...payment,
        refundedBeforePaise: 0,
        refundedPaise: 112_100,
      }),
    ).toBe(17_100);
  });

  it('is proportional on a partial refund', () => {
    expect(
      refundTaxPaise({
        ...payment,
        refundedBeforePaise: 0,
        refundedPaise: 56_050,
      }),
    ).toBe(8_550);
  });

  it('adds up to exactly the GST however the refund is split', () => {
    const pieces = [1, 333, 10_000, 40_000, 61_766];
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

  it('is 0 while no GST is charged', () => {
    expect(
      refundTaxPaise({
        amountPaidPaise: 95_000,
        taxPaise: 0,
        refundedBeforePaise: 0,
        refundedPaise: 40_000,
      }),
    ).toBe(0);
  });

  it('refuses refunds beyond what was paid', () => {
    expect(() =>
      refundTaxPaise({
        ...payment,
        refundedBeforePaise: 100_000,
        refundedPaise: 12_101,
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
