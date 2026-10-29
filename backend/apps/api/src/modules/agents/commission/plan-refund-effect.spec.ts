import {
  planRefundEffect,
  reduceForRefund,
  RefundCommissionStatus,
  RefundEffectInput,
} from './plan-refund-effect';

const input = (
  overrides: Partial<RefundEffectInput> = {},
): RefundEffectInput => ({
  commissionStatus: 'APPROVED',
  creditedPaise: 10_000,
  alreadyReversedPaise: 0,
  amountPaidPaise: 100_000,
  refundedTotalPaise: 100_000,
  isFullRefund: true,
  payoutStatus: 'NONE',
  ...overrides,
});

const partial = (overrides: Partial<RefundEffectInput> = {}) =>
  input({ isFullRefund: false, ...overrides });

describe('planRefundEffect', () => {
  describe('already closed', () => {
    it.each(['CANCELLED', 'REVERSED'] as const)(
      '%s is UNCHANGED with nothing to reverse',
      (commissionStatus) => {
        expect(
          planRefundEffect(input({ commissionStatus, payoutStatus: 'PAID' })),
        ).toEqual({
          commissionNext: 'UNCHANGED',
          reversalPaise: 0,
          balanceMayGoNegative: false,
        });
      },
    );
  });

  describe('before approval nothing was credited', () => {
    it.each([
      'ON_HOLD',
      'AWAITING_VERIFICATION',
      'IN_REVIEW',
      'FROZEN',
      'READY',
    ] as const)(
      '%s -> CANCELLED, no reversal (full refund)',
      (commissionStatus) => {
        expect(planRefundEffect(input({ commissionStatus }))).toEqual({
          commissionNext: 'CANCELLED',
          reversalPaise: 0,
          balanceMayGoNegative: false,
        });
      },
    );

    it('a PARTIAL refund REDUCES the commission in proportion instead (DECIDED, Ishu 29 Oct)', () => {
      // 25% refunded: floor(10_000 * 75_000 / 100_000) = 7_500 is left.
      expect(
        planRefundEffect(
          partial({
            commissionStatus: 'ON_HOLD',
            refundedTotalPaise: 25_000,
            originalAmountPaise: 10_000,
          }),
        ),
      ).toEqual({
        commissionNext: 'REDUCED',
        reversalPaise: 0,
        balanceMayGoNegative: false,
        refundedPaise: 25_000,
        reducedAmountPaise: 7_500,
      });
    });

    it('uses the running total on the ORIGINAL amount, so pieces end where one refund would', () => {
      const after = (total: number, already: number) =>
        planRefundEffect(
          partial({
            commissionStatus: 'READY',
            refundedTotalPaise: total,
            alreadyRefundedPaise: already,
            originalAmountPaise: 10_001,
          }),
        ).reducedAmountPaise;
      // 33_333 then 66_666 refunded in total, against one refund of 66_666.
      expect(after(33_333, 0)).toBe(6_667);
      expect(after(66_666, 33_333)).toBe(3_333);
      expect(after(66_666, 0)).toBe(3_333);
    });

    it('rounds down and is exact for very large amounts (BigInt)', () => {
      expect(reduceForRefund(1, 3, 1)).toBe(0);
      expect(reduceForRefund(10, 3, 1)).toBe(6);
      const big = 9_000_000_000_000_000;
      expect(reduceForRefund(big, big, 1)).toBe(big - 1);
      expect(reduceForRefund(big, big, big)).toBe(0);
      // Floating point would give ...951 here; integer maths gives ...950.
      expect(
        reduceForRefund(5_396_221_036_765_083, 9_007_199_253_998_632, 221),
      ).toBe(5_396_221_036_764_950);
    });

    it('a replayed refund (same or older running total) changes nothing', () => {
      for (const total of [25_000, 10_000]) {
        expect(
          planRefundEffect(
            partial({
              commissionStatus: 'ON_HOLD',
              refundedTotalPaise: total,
              alreadyRefundedPaise: 25_000,
              originalAmountPaise: 10_000,
            }),
          ),
        ).toEqual({
          commissionNext: 'UNCHANGED',
          reversalPaise: 0,
          balanceMayGoNegative: false,
        });
      }
    });

    it('with no amount yet the refund is recorded and the amount stays unknown', () => {
      expect(
        planRefundEffect(
          partial({
            commissionStatus: 'ON_HOLD',
            refundedTotalPaise: 25_000,
            originalAmountPaise: null,
          }),
        ),
      ).toMatchObject({
        commissionNext: 'REDUCED',
        refundedPaise: 25_000,
        reducedAmountPaise: null,
      });
    });

    it('a refund of everything cancels even when not flagged as the full one', () => {
      expect(
        planRefundEffect(
          partial({
            commissionStatus: 'ON_HOLD',
            refundedTotalPaise: 100_000,
            originalAmountPaise: 10_000,
          }),
        ).commissionNext,
      ).toBe('CANCELLED');
    });

    it('never flags a negative balance', () => {
      expect(
        planRefundEffect(
          input({ commissionStatus: 'READY', payoutStatus: 'PAID' }),
        ).balanceMayGoNegative,
      ).toBe(false);
    });
  });

  describe('full refund after approval', () => {
    it.each(['APPROVED', 'PAID'] as const)(
      '%s -> REVERSED for the whole credited amount',
      (commissionStatus) => {
        expect(planRefundEffect(input({ commissionStatus }))).toEqual({
          commissionNext: 'REVERSED',
          reversalPaise: 10_000,
          balanceMayGoNegative: false,
        });
      },
    );

    it('reverses only what is left after earlier partial reversals', () => {
      expect(
        planRefundEffect(input({ alreadyReversedPaise: 4_000 })),
      ).toMatchObject({ commissionNext: 'REVERSED', reversalPaise: 6_000 });
    });

    it('is REVERSED with nothing more to reverse when all was already reversed', () => {
      expect(
        planRefundEffect(input({ alreadyReversedPaise: 10_000 })),
      ).toMatchObject({ commissionNext: 'REVERSED', reversalPaise: 0 });
    });
  });

  describe('partial refunds after approval', () => {
    it.each(['APPROVED', 'PAID'] as const)(
      'a first partial refund keeps %s and reverses in proportion',
      (commissionStatus) => {
        // 25% refunded -> 25% of 10,000.
        expect(
          planRefundEffect(
            partial({ commissionStatus, refundedTotalPaise: 25_000 }),
          ),
        ).toEqual({
          commissionNext: 'UNCHANGED',
          reversalPaise: 2_500,
          balanceMayGoNegative: false,
        });
      },
    );

    it('a second partial refund claws back only the difference', () => {
      // 60% refunded in total: 6,000 owed, 2,500 already reversed.
      expect(
        planRefundEffect(
          partial({ refundedTotalPaise: 60_000, alreadyReversedPaise: 2_500 }),
        ),
      ).toMatchObject({ commissionNext: 'UNCHANGED', reversalPaise: 3_500 });
    });

    it('a third refund that completes the credit gives REVERSED', () => {
      // Refunded total reaches 100% although it is not flagged as the full one.
      expect(
        planRefundEffect(
          partial({ refundedTotalPaise: 100_000, alreadyReversedPaise: 6_000 }),
        ),
      ).toMatchObject({ commissionNext: 'REVERSED', reversalPaise: 4_000 });
    });

    it('a repeated identical refund reverses nothing', () => {
      const first = planRefundEffect(partial({ refundedTotalPaise: 25_000 }));
      expect(first.reversalPaise).toBe(2_500);
      const repeat = planRefundEffect(
        partial({ refundedTotalPaise: 25_000, alreadyReversedPaise: 2_500 }),
      );
      expect(repeat).toEqual({
        commissionNext: 'UNCHANGED',
        reversalPaise: 0,
        balanceMayGoNegative: false,
      });
    });

    it('rounds down', () => {
      // 10,000 * 1 / 3 = 3333.33 -> 3333
      expect(
        planRefundEffect(
          partial({ amountPaidPaise: 3, refundedTotalPaise: 1 }),
        ),
      ).toMatchObject({ commissionNext: 'UNCHANGED', reversalPaise: 3_333 });
      // 999 * 1 / 2 = 499.5 -> 499
      expect(
        planRefundEffect(
          partial({
            creditedPaise: 999,
            amountPaidPaise: 2,
            refundedTotalPaise: 1,
          }),
        ).reversalPaise,
      ).toBe(499);
    });

    it('can round to zero and stays unchanged', () => {
      expect(
        planRefundEffect(
          partial({
            creditedPaise: 1,
            amountPaidPaise: 100,
            refundedTotalPaise: 1,
          }),
        ),
      ).toMatchObject({ commissionNext: 'UNCHANGED', reversalPaise: 0 });
    });

    it('is never below zero when more was already reversed than is owed now', () => {
      expect(
        planRefundEffect(
          partial({ refundedTotalPaise: 10_000, alreadyReversedPaise: 5_000 }),
        ),
      ).toMatchObject({ commissionNext: 'UNCHANGED', reversalPaise: 0 });
    });

    it('is never above what is left to reverse', () => {
      expect(
        planRefundEffect(
          partial({ refundedTotalPaise: 100_000, alreadyReversedPaise: 7_000 }),
        ),
      ).toMatchObject({ commissionNext: 'REVERSED', reversalPaise: 3_000 });
    });

    it('treats an already-over-reversed credit as fully reversed, with nothing more', () => {
      expect(
        planRefundEffect(partial({ alreadyReversedPaise: 12_000 })),
      ).toMatchObject({ commissionNext: 'REVERSED', reversalPaise: 0 });
    });

    it('is exact for very large amounts', () => {
      // 9e12 * 4.5e12 overflows double precision; BigInt keeps it exact.
      expect(
        planRefundEffect(
          partial({
            creditedPaise: 9_000_000_000_000,
            amountPaidPaise: 9_000_000_000_000,
            refundedTotalPaise: 4_500_000_000_001,
          }),
        ),
      ).toMatchObject({
        commissionNext: 'UNCHANGED',
        reversalPaise: 4_500_000_000_001,
      });
    });
  });

  describe('zero credit', () => {
    it.each(['APPROVED', 'PAID'] as const)(
      '%s with creditedPaise 0 is UNCHANGED with nothing to reverse',
      (commissionStatus) => {
        expect(
          planRefundEffect(
            input({
              commissionStatus,
              creditedPaise: 0,
              payoutStatus: 'PAID',
            }),
          ),
        ).toEqual({
          commissionNext: 'UNCHANGED',
          reversalPaise: 0,
          balanceMayGoNegative: false,
        });
      },
    );
  });

  describe('balanceMayGoNegative', () => {
    it('is true when the payout was PAID and a full refund reverses something', () => {
      expect(
        planRefundEffect(
          input({ commissionStatus: 'PAID', payoutStatus: 'PAID' }),
        ),
      ).toMatchObject({
        commissionNext: 'REVERSED',
        reversalPaise: 10_000,
        balanceMayGoNegative: true,
      });
    });

    it('is true when the payout was PAID and a partial refund reverses something', () => {
      expect(
        planRefundEffect(
          partial({
            commissionStatus: 'PAID',
            payoutStatus: 'PAID',
            refundedTotalPaise: 25_000,
          }),
        ),
      ).toMatchObject({
        commissionNext: 'UNCHANGED',
        reversalPaise: 2_500,
        balanceMayGoNegative: true,
      });
    });

    it('is false when the payout was PAID but nothing is reversed', () => {
      expect(
        planRefundEffect(
          input({
            commissionStatus: 'PAID',
            payoutStatus: 'PAID',
            alreadyReversedPaise: 10_000,
          }),
        ),
      ).toMatchObject({ reversalPaise: 0, balanceMayGoNegative: false });
    });

    it('is false when no payout has been made', () => {
      expect(
        planRefundEffect(
          input({ commissionStatus: 'APPROVED', payoutStatus: 'NONE' }),
        ).balanceMayGoNegative,
      ).toBe(false);
    });
  });

  describe('every status', () => {
    const fullRefund: Record<RefundCommissionStatus, string> = {
      ON_HOLD: 'CANCELLED',
      AWAITING_VERIFICATION: 'CANCELLED',
      IN_REVIEW: 'CANCELLED',
      FROZEN: 'CANCELLED',
      READY: 'CANCELLED',
      APPROVED: 'REVERSED',
      PAID: 'REVERSED',
      CANCELLED: 'UNCHANGED',
      REVERSED: 'UNCHANGED',
    };
    it.each(Object.entries(fullRefund))(
      'full refund: %s -> %s',
      (status, next) => {
        expect(
          planRefundEffect(
            input({ commissionStatus: status as RefundCommissionStatus }),
          ).commissionNext,
        ).toBe(next);
      },
    );

    const firstPartial: Record<RefundCommissionStatus, string> = {
      ...fullRefund,
      ON_HOLD: 'REDUCED',
      AWAITING_VERIFICATION: 'REDUCED',
      IN_REVIEW: 'REDUCED',
      FROZEN: 'REDUCED',
      READY: 'REDUCED',
      APPROVED: 'UNCHANGED',
      PAID: 'UNCHANGED',
    };
    it.each(Object.entries(firstPartial))(
      'first partial refund: %s -> %s',
      (status, next) => {
        expect(
          planRefundEffect(
            partial({
              commissionStatus: status as RefundCommissionStatus,
              refundedTotalPaise: 25_000,
              originalAmountPaise: 10_000,
            }),
          ).commissionNext,
        ).toBe(next);
      },
    );
  });

  describe('after approval, when a refund already reduced the commission before it', () => {
    // Original 10_000; 40% refunded before approval left 6_000, which was credited.
    const later = (over: Partial<RefundEffectInput>) =>
      planRefundEffect(
        partial({
          creditedPaise: 6_000,
          originalAmountPaise: 10_000,
          ...over,
        }),
      );

    it('reverses only down to what the running total leaves of the ORIGINAL', () => {
      // 70% refunded in total: 3_000 should remain, so 3_000 is reversed.
      expect(later({ refundedTotalPaise: 70_000 })).toMatchObject({
        commissionNext: 'UNCHANGED',
        reversalPaise: 3_000,
      });
    });

    it('subtracts what was already reversed, and never goes negative', () => {
      expect(
        later({ refundedTotalPaise: 70_000, alreadyReversedPaise: 3_000 }),
      ).toMatchObject({ reversalPaise: 0 });
      expect(
        later({ refundedTotalPaise: 70_000, alreadyReversedPaise: 1_000 }),
      ).toMatchObject({ reversalPaise: 2_000 });
    });

    it('a full refund reverses all that is left and marks it REVERSED', () => {
      expect(later({ isFullRefund: true })).toMatchObject({
        commissionNext: 'REVERSED',
        reversalPaise: 6_000,
      });
    });

    it('without a reduction the old proportional rule applies', () => {
      expect(
        planRefundEffect(
          partial({ creditedPaise: 10_000, refundedTotalPaise: 25_000 }),
        ).reversalPaise,
      ).toBe(2_500);
    });
  });

  describe('invalid inputs', () => {
    const fields = [
      'creditedPaise',
      'alreadyReversedPaise',
      'amountPaidPaise',
      'refundedTotalPaise',
    ] as const;

    for (const field of fields) {
      it.each([-1, 1.5, NaN, Infinity])(`rejects ${field} = %p`, (value) => {
        expect(() => planRefundEffect(input({ [field]: value }))).toThrow(
          RangeError,
        );
      });
    }

    it('rejects amountPaidPaise of zero', () => {
      expect(() =>
        planRefundEffect(input({ amountPaidPaise: 0, refundedTotalPaise: 0 })),
      ).toThrow(RangeError);
    });

    it('rejects a refunded total above the amount paid', () => {
      expect(() =>
        planRefundEffect(input({ refundedTotalPaise: 100_001 })),
      ).toThrow(RangeError);
    });

    it('validates before looking at the status', () => {
      expect(() =>
        planRefundEffect(
          input({ commissionStatus: 'CANCELLED', creditedPaise: -1 }),
        ),
      ).toThrow(RangeError);
    });
  });
});
