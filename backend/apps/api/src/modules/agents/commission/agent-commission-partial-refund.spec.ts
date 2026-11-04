/**
 * DECIDED (Ishu, 29 Oct): a PARTIAL refund before approval REDUCES the
 * commission in proportion; a full refund cancels it. And: GST rate 0
 * (Raja is not registered for GST yet) behaves like any other rate.
 *
 * Numbers (GST-exclusive prices, 18%): taxable 9500, GST 1710, the member
 * paid 11210, the commission is 10% of the taxable amount = 950.
 *   refunded 2802 -> floor(950 * (11210 - 2802) / 11210) = 712 left
 *   refunded 5605 -> floor(950 * (11210 - 5605) / 11210) = 475 left
 * At GST 0: paid = taxable = 9500, commission 950;
 *   refunded 2375 -> floor(950 * (9500 - 2375) / 9500) = 712 left.
 */
import {
  DAY,
  HOUR,
  T0,
  makeCommissionHarness,
  type CommissionHarness,
} from '../testing/agent-commission-harness';

let h: CommissionHarness;
const HOLD_END = new Date(T0.getTime() + HOUR + 14 * DAY);

const partialRefund = (refundN: number, total: number, n = 1) =>
  h.paymentRefunded(n, refundN, {
    refundedPaise: total,
    totalRefundedPaise: total,
    fullyRefunded: false,
  });

const GST0 = {
  amountPaidPaise: 9_500,
  taxRateBps: 0,
  taxPaise: 0,
  taxableAmountPaise: 9_500,
};

beforeEach(() => {
  h = makeCommissionHarness();
  h.seedPolicy();
});

const commission = (n = 1) => h.commissions.findByPaymentId(`pay-${n}`);

describe('a partial refund before approval reduces the commission in proportion', () => {
  it.each([
    'ON_HOLD',
    'AWAITING_VERIFICATION',
    'IN_REVIEW',
    'FROZEN',
    'READY',
  ] as const)(
    '%s: reduced, the status stays, the ledger is untouched',
    async (status) => {
      await h.seedCommission(1, { status });
      const auditBefore = h.audit.entries.length;
      const result = await h.events.onPaymentRefunded(partialRefund(1, 2_802));
      expect(result).toMatchObject({
        outcome: 'REDUCED',
        reducedAmountPaise: 712,
      });
      expect(await commission()).toMatchObject({
        status,
        amountPaise: 712,
        preRefundAmountPaise: 950,
        refundedPaise: 2_802,
        creditedPaise: 0,
        reversedPaise: 0,
      });
      expect(h.ledger.all).toHaveLength(0);
      expect(h.audit.entries.length).toBe(auditBefore + 1);
      expect(h.audit.entries.at(-1)?.action).toBe(
        'COMMISSION_REDUCED_BY_REFUND',
      );
    },
  );

  it('keeps the rule snapshot, the review reasons and the hold', async () => {
    const before = await h.seedCommission(1, {
      status: 'IN_REVIEW',
      reviewReasons: ['PAID_BY_AGENT', 'SELF_MATCH'],
    });
    await h.events.onPaymentRefunded(partialRefund(1, 2_802));
    expect(await commission()).toMatchObject({
      status: 'IN_REVIEW',
      reviewReasons: ['PAID_BY_AGENT', 'SELF_MATCH'],
      calcType: before.calcType,
      ruleValue: before.ruleValue,
      policyVersionId: before.policyVersionId,
      basePaise: before.basePaise,
      holdUntil: before.holdUntil,
      amountPaidPaise: 11_210,
      taxableAmountPaise: 9_500,
    });
  });

  it('uses the running total on the original: pieces end where one refund would', async () => {
    await h.seedCommission(1);
    await h.events.onPaymentRefunded(partialRefund(1, 2_802));
    expect((await commission())?.amountPaise).toBe(712);
    await h.events.onPaymentRefunded(partialRefund(2, 5_605));
    expect((await commission())?.amountPaise).toBe(475);

    const hh = makeCommissionHarness();
    hh.seedPolicy();
    await hh.seedCommission(1);
    await hh.events.onPaymentRefunded(
      hh.paymentRefunded(1, 1, {
        refundedPaise: 5_605,
        totalRefundedPaise: 5_605,
        fullyRefunded: false,
      }),
    );
    expect((await hh.commissions.findByPaymentId('pay-1'))?.amountPaise).toBe(
      475,
    );
  });

  it('is idempotent per refund: a replay, or an older refund arriving late, changes nothing', async () => {
    await h.seedCommission(1);
    await h.events.onPaymentRefunded(partialRefund(1, 2_802));
    await h.events.onPaymentRefunded(partialRefund(2, 5_605));
    const auditCount = h.audit.entries.length;
    const state = await commission();
    for (const replay of [partialRefund(2, 5_605), partialRefund(1, 2_802)]) {
      expect((await h.events.onPaymentRefunded(replay)).outcome).toBe(
        'NOTHING_TO_REVERSE',
      );
    }
    expect(await commission()).toEqual(state);
    expect(h.audit.entries).toHaveLength(auditCount);
  });

  it('two deliveries of one refund at once reduce it once', async () => {
    await h.seedCommission(1);
    await Promise.all([
      h.events.onPaymentRefunded(partialRefund(1, 2_802)),
      h.events.onPaymentRefunded(partialRefund(1, 2_802)),
    ]);
    expect((await commission())?.amountPaise).toBe(712);
    expect((await commission())?.refundedPaise).toBe(2_802);
  });

  it('a full refund still cancels it, after earlier partial ones too', async () => {
    await h.seedCommission(1);
    await h.events.onPaymentRefunded(partialRefund(1, 2_802));
    const result = await h.events.onPaymentRefunded(h.paymentRefunded(1, 2));
    expect(result.outcome).toBe('CANCELLED');
    expect(await commission()).toMatchObject({ status: 'CANCELLED' });
    expect(h.ledger.all).toHaveLength(0);
  });

  it('refunding everything in pieces cancels it', async () => {
    await h.seedCommission(1);
    const result = await h.events.onPaymentRefunded(partialRefund(1, 11_210));
    expect(result.outcome).toBe('CANCELLED');
  });

  it('a failed audit write undoes the reduction', async () => {
    await h.seedCommission(1);
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(
      h.events.onPaymentRefunded(partialRefund(1, 2_802)),
    ).rejects.toThrow('audit down');
    expect(await commission()).toMatchObject({
      amountPaise: 950,
      refundedPaise: 0,
      preRefundAmountPaise: null,
    });
  });

  it('losing a race throws so the event is retried', async () => {
    await h.seedCommission(1);
    jest.spyOn(h.commissions, 'transition').mockResolvedValueOnce(null);
    await expect(
      h.events.onPaymentRefunded(partialRefund(1, 2_802)),
    ).rejects.toMatchObject({ code: 'CONCURRENT_CHANGE' });
    expect((await commission())?.amountPaise).toBe(950);
  });
});

describe('the reduced amount is what gets approved and credited', () => {
  it('approval credits the reduced amount', async () => {
    await h.seedCommission(1);
    await h.events.onPaymentRefunded(partialRefund(1, 2_802));
    await h.approval.runDailyApproval(HOLD_END, 10);
    expect(await commission()).toMatchObject({
      status: 'APPROVED',
      amountPaise: 712,
      creditedPaise: 712,
    });
    expect(await h.ledger.balance('agent-1')).toBe(712);
  });

  it('a refund after approval reverses down to what the running total leaves of the original', async () => {
    await h.seedCommission(1);
    await h.events.onPaymentRefunded(partialRefund(1, 2_802));
    await h.approval.runDailyApproval(HOLD_END, 10);
    const result = await h.events.onPaymentRefunded(partialRefund(2, 5_605));
    // 475 should remain of the original 950; 712 was credited.
    expect(result).toMatchObject({ outcome: 'REVERSED', reversalPaise: 237 });
    expect(await h.ledger.balance('agent-1')).toBe(475);
    // And the final full refund takes the rest.
    await h.events.onPaymentRefunded(h.paymentRefunded(1, 3));
    expect(await h.ledger.balance('agent-1')).toBe(0);
    expect((await commission())?.status).toBe('REVERSED');
  });
});

describe('a partial refund before the commission base is set', () => {
  it('is recorded, and the late fill applies the same refunded fraction', async () => {
    h.settings.set('commission.base', null);
    await h.seedCommission(1);
    expect((await commission())?.amountPaise).toBeNull();

    const result = await h.events.onPaymentRefunded(partialRefund(1, 2_802));
    expect(result).toMatchObject({
      outcome: 'REDUCED',
      reducedAmountPaise: null,
    });
    expect(await commission()).toMatchObject({
      amountPaise: null,
      refundedPaise: 2_802,
      status: 'ON_HOLD',
    });

    h.settings.set('commission.base', 'AMOUNT_PAID_EXCLUDING_GST');
    await h.approval.runDailyApproval(HOLD_END, 10);
    // Not the full 950: a later base does not undo the refund.
    expect(await commission()).toMatchObject({
      status: 'APPROVED',
      basePaise: 9_500,
      amountPaise: 712,
      preRefundAmountPaise: 950,
      creditedPaise: 712,
    });
  });

  it('further refunds before the base is set only raise the running total', async () => {
    h.settings.set('commission.base', null);
    await h.seedCommission(1);
    await h.events.onPaymentRefunded(partialRefund(1, 2_802));
    await h.events.onPaymentRefunded(partialRefund(2, 5_605));
    h.settings.set('commission.base', 'AMOUNT_PAID_EXCLUDING_GST');
    await h.approval.runDailyApproval(HOLD_END, 10);
    expect((await commission())?.amountPaise).toBe(475);
  });

  it('a full refund before the base is set still cancels', async () => {
    h.settings.set('commission.base', null);
    await h.seedCommission(1);
    expect(
      (await h.events.onPaymentRefunded(h.paymentRefunded(1, 1))).outcome,
    ).toBe('CANCELLED');
  });
});

describe('GST rate 0 (not registered for GST yet)', () => {
  const gst0 = (n = 1) => h.paymentSucceeded(n, GST0);

  it.each(['AMOUNT_PAID_EXCLUDING_GST', 'AMOUNT_PAID'] as const)(
    'the draft: tax 0, taxable equals the amount paid, base %s equals the amount paid',
    async (base) => {
      h.settings.set('commission.base', base);
      await h.seedAgent();
      await h.seedAttribution(1);
      await h.events.onPaymentSucceeded(gst0());
      expect(await commission()).toMatchObject({
        basePaise: 9_500,
        amountPaise: 950,
        amountPaidPaise: 9_500,
        taxableAmountPaise: 9_500,
      });
    },
  );

  it('the event must still add up (tax 0 + taxable == paid)', async () => {
    await h.seedAgent();
    await h.seedAttribution(1);
    await expect(
      h.events.onPaymentSucceeded(
        h.paymentSucceeded(1, { ...GST0, taxableAmountPaise: 9_000 }),
      ),
    ).rejects.toThrow(RangeError);
  });

  it('the late fill: the same base either way', async () => {
    h.settings.set('commission.base', null);
    await h.seedAgent();
    await h.seedAttribution(1);
    await h.events.onPaymentSucceeded(gst0());
    expect((await commission())?.amountPaise).toBeNull();
    h.settings.set('commission.base', 'AMOUNT_PAID_EXCLUDING_GST');
    await h.approval.runDailyApproval(HOLD_END, 10);
    expect(await commission()).toMatchObject({
      status: 'APPROVED',
      basePaise: 9_500,
      amountPaise: 950,
      creditedPaise: 950,
    });
  });

  it('the cap is the amount paid, which equals the taxable amount at rate 0', async () => {
    h.settings.set('commission.base', 'AMOUNT_PAID');
    h.seedPolicy({ id: 'pol-9', version: 9, value: 10_000 });
    await h.seedAgent();
    await h.seedAttribution(1);
    await h.events.onPaymentSucceeded(gst0());
    expect((await commission())?.amountPaise).toBe(9_500);
  });

  it('a full refund cancels it', async () => {
    await h.seedAgent();
    await h.seedAttribution(1);
    await h.events.onPaymentSucceeded(gst0());
    const result = await h.events.onPaymentRefunded(
      h.paymentRefunded(1, 1, {
        refundedPaise: 9_500,
        refundedTaxPaise: 0,
        totalRefundedPaise: 9_500,
      }),
    );
    expect(result.outcome).toBe('CANCELLED');
  });

  it('a partial refund reduces it: floor(950 * (9500 - 2375) / 9500) = 712', async () => {
    await h.seedAgent();
    await h.seedAttribution(1);
    await h.events.onPaymentSucceeded(gst0());
    const result = await h.events.onPaymentRefunded(
      h.paymentRefunded(1, 1, {
        refundedPaise: 2_375,
        refundedTaxPaise: 0,
        totalRefundedPaise: 2_375,
        fullyRefunded: false,
      }),
    );
    expect(result).toMatchObject({
      outcome: 'REDUCED',
      reducedAmountPaise: 712,
    });
  });

  it('after approval a partial refund reverses in proportion', async () => {
    await h.seedAgent();
    await h.seedAttribution(1);
    await h.events.onPaymentSucceeded(gst0());
    await h.approval.runDailyApproval(HOLD_END, 10);
    const result = await h.events.onPaymentRefunded(
      h.paymentRefunded(1, 1, {
        refundedPaise: 2_375,
        refundedTaxPaise: 0,
        totalRefundedPaise: 2_375,
        fullyRefunded: false,
      }),
    );
    // floor(950 * 2375 / 9500) = 237
    expect(result).toMatchObject({ outcome: 'REVERSED', reversalPaise: 237 });
  });
});
