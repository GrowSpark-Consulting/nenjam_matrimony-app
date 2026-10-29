import { AgentMoneyError } from '../errors/agent-money-error';
import { AgentConflictError } from '../ports/agent-data-ports';
import {
  DAY,
  HOUR,
  T0,
  makeCommissionHarness,
  type CommissionHarness,
} from '../testing/agent-commission-harness';
import { AgentCommissionPolicyMissingError } from './agent-commission-events.service';

let h: CommissionHarness;

beforeEach(async () => {
  h = makeCommissionHarness();
  h.seedPolicy();
  await h.seedAgent();
  await h.seedAttribution(1);
});

describe('onPaymentSucceeded', () => {
  it('creates an ON_HOLD commission on the stored taxable amount', async () => {
    const result = await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
    expect(result.outcome).toBe('CREATED');
    const commission = await h.commissions.findByPaymentId('pay-1');
    expect(commission).toMatchObject({
      agentId: 'agent-1',
      attributionId: 'attr-1',
      phoneHash: 'v1:member-hash-1',
      policyVersionId: 'pol-1',
      status: 'ON_HOLD',
      calcType: 'PERCENTAGE',
      ruleValue: 1000,
      basePaise: 8051, // commission.base AMOUNT_PAID_EXCLUDING_GST: the stored taxable amount
      amountPaise: 805, // 10% of 8051, rounded down
      amountPaidPaise: 9500,
      taxableAmountPaise: 8051,
      creditedPaise: 0,
      reversedPaise: 0,
      reviewReasons: [],
    });
    expect(commission?.holdUntil).toEqual(
      new Date(T0.getTime() + HOUR + 14 * DAY),
    );
    // Nothing is credited before approval.
    expect(h.ledger.all).toHaveLength(0);
    expect(h.audit.entries.map((e) => e.action)).toEqual([
      'COMMISSION_CREATED',
    ]);
  });

  it('uses the amount paid when commission.base is AMOUNT_PAID', async () => {
    h.settings.set('commission.base', 'AMOUNT_PAID');
    await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
    expect(await h.commissions.findByPaymentId('pay-1')).toMatchObject({
      basePaise: 9500,
      amountPaise: 950,
    });
  });

  it.each([null, 'unset'])(
    'leaves the amount empty when commission.base is %s',
    async (value) => {
      if (value === 'unset') h.settings.remove('commission.base');
      else h.settings.set('commission.base', value);
      await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
      expect(await h.commissions.findByPaymentId('pay-1')).toMatchObject({
        basePaise: null,
        amountPaise: null,
        taxableAmountPaise: 8051,
      });
    },
  );

  it('NEVER recomputes the tax: the stored taxable amount is used as given', async () => {
    // 18% of 9500 would give 8051, but the payment stored something else.
    await h.events.onPaymentSucceeded(
      h.paymentSucceeded(1, { taxableAmountPaise: 5_000, taxPaise: 4_500 }),
    );
    expect(await h.commissions.findByPaymentId('pay-1')).toMatchObject({
      basePaise: 5000,
      amountPaise: 500,
    });
  });

  it('refuses an event whose tax and taxable amount do not add up to what was paid', async () => {
    await expect(
      h.events.onPaymentSucceeded(h.paymentSucceeded(1, { taxPaise: 1_000 })),
    ).rejects.toThrow(RangeError);
    expect(await h.commissions.findByPaymentId('pay-1')).toBeNull();
  });

  it.each([
    ['paymentId', { paymentId: '' }],
    ['memberId', { memberId: ' ' }],
    ['amountPaidPaise', { amountPaidPaise: -1 }],
    ['paidAt', { paidAt: 'not a date' }],
  ])('refuses an event with a bad %s', async (_field, override) => {
    await expect(
      h.events.onPaymentSucceeded(h.paymentSucceeded(1, override)),
    ).rejects.toThrow(RangeError);
  });

  describe('idempotency, keyed on the payment id', () => {
    it('a replayed event creates nothing more', async () => {
      const first = await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
      const again = await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
      expect(again.outcome).toBe('ALREADY_PROCESSED');
      expect(again.commissionId).toBe(first.commissionId);
      expect((await h.commissions.listPage({}, { limit: 10 })).length).toBe(1);
      expect(h.audit.entries).toHaveLength(1);
    });

    it('two deliveries at once create one commission', async () => {
      const results = await Promise.all([
        h.events.onPaymentSucceeded(h.paymentSucceeded(1)),
        h.events.onPaymentSucceeded(h.paymentSucceeded(1)),
      ]);
      expect(results.map((r) => r.outcome).sort()).toEqual([
        'ALREADY_PROCESSED',
        'CREATED',
      ]);
      expect((await h.commissions.listPage({}, { limit: 10 })).length).toBe(1);
    });

    it('losing the race at the database (duplicate) answers ALREADY_PROCESSED', async () => {
      await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
      jest.spyOn(h.commissions, 'findByPaymentId').mockResolvedValueOnce(null); // not seen inside the transaction ...
      jest
        .spyOn(h.commissions, 'create')
        .mockRejectedValueOnce(new AgentConflictError('DUPLICATE_COMMISSION'));
      const result = await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
      expect(result.outcome).toBe('ALREADY_PROCESSED'); // ... but found afterwards
      expect(result.commissionId).toBeDefined();
    });

    it('a second payment for the same referral earns nothing more', async () => {
      await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
      const second = await h.events.onPaymentSucceeded(
        h.paymentSucceeded(2, { memberId: 'member-1' }),
      );
      expect(second.outcome).toBe('ALREADY_PROCESSED');
      expect((await h.commissions.listPage({}, { limit: 10 })).length).toBe(1);
    });
  });

  describe('who earns', () => {
    it('only a first paid plan earns', async () => {
      const result = await h.events.onPaymentSucceeded(
        h.paymentSucceeded(1, { isFirstPaidPlan: false }),
      );
      expect(result.outcome).toBe('NOT_FIRST_PLAN');
      expect(await h.commissions.findByPaymentId('pay-1')).toBeNull();
    });

    it('a member nobody referred earns nobody anything', async () => {
      const result = await h.events.onPaymentSucceeded(
        h.paymentSucceeded(9, { memberId: 'unreferred' }),
      );
      expect(result.outcome).toBe('NO_ATTRIBUTION');
    });

    it.each(['REJECTED', 'EXPIRED', 'CONVERTED'] as const)(
      'an attribution that is %s earns nothing',
      async (status) => {
        const hh = makeCommissionHarness();
        hh.seedPolicy();
        await hh.seedAgent();
        await hh.seedAttribution(1, { status });
        const result = await hh.events.onPaymentSucceeded(
          hh.paymentSucceeded(1),
        );
        expect(result.outcome).toBe('ATTRIBUTION_NOT_ACTIVE');
        expect(await hh.commissions.findByPaymentId('pay-1')).toBeNull();
      },
    );

    it('a payment after the credit window earns nothing; on the last moment it earns', async () => {
      const windowEnd = new Date(T0.getTime() + 10 * DAY);
      const hh = makeCommissionHarness();
      hh.seedPolicy();
      await hh.seedAgent();
      await hh.seedAttribution(1, { windowEndsAt: windowEnd });
      await hh.seedAttribution(2, { windowEndsAt: windowEnd });
      expect(
        (
          await hh.events.onPaymentSucceeded(
            hh.paymentSucceeded(1, {
              paidAt: new Date(windowEnd.getTime() + 1).toISOString(),
            }),
          )
        ).outcome,
      ).toBe('OUTSIDE_CREDIT_WINDOW');
      expect(
        (
          await hh.events.onPaymentSucceeded(
            hh.paymentSucceeded(2, { paidAt: windowEnd.toISOString() }),
          )
        ).outcome,
      ).toBe('CREATED');
    });
  });

  describe('review flags', () => {
    it('a payment recorded by an admin is not flagged', async () => {
      await h.events.onPaymentSucceeded(
        h.paymentSucceeded(1, { paidBy: 'ADMIN_RECORDED' }),
      );
      expect((await h.commissions.findByPaymentId('pay-1'))?.status).toBe(
        'ON_HOLD',
      );
    });

    it('a payment made by the agent goes to review', async () => {
      await h.events.onPaymentSucceeded(
        h.paymentSucceeded(1, { paidBy: 'AGENT' }),
      );
      expect(await h.commissions.findByPaymentId('pay-1')).toMatchObject({
        status: 'IN_REVIEW',
        reviewReasons: ['PAID_BY_AGENT'],
      });
    });

    it('a payment source already used by another member goes to review', async () => {
      h.paymentSources.used.add('src-1');
      await h.events.onPaymentSucceeded(
        h.paymentSucceeded(1, { paymentSourceHash: 'src-1' }),
      );
      expect(await h.commissions.findByPaymentId('pay-1')).toMatchObject({
        status: 'IN_REVIEW',
        reviewReasons: ['PAYMENT_SOURCE_REUSED'],
      });
    });

    it('the payment source is not looked up when the payment has none', async () => {
      await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
      expect(h.paymentSources.calls).toBe(0);
    });

    it("a member whose phone is the agent's own goes to review (self match)", async () => {
      const hh = makeCommissionHarness();
      hh.seedPolicy();
      await hh.seedAgent('ACTIVE', { phoneHash: 'v1:same' });
      await hh.seedAttribution(1, { memberPhoneHash: 'v1:same' });
      await hh.events.onPaymentSucceeded(hh.paymentSucceeded(1));
      expect(await hh.commissions.findByPaymentId('pay-1')).toMatchObject({
        status: 'IN_REVIEW',
        reviewReasons: ['SELF_MATCH'],
      });
    });

    it('several flags are all recorded', async () => {
      h.paymentSources.used.add('src-1');
      await h.events.onPaymentSucceeded(
        h.paymentSucceeded(1, { paidBy: 'AGENT', paymentSourceHash: 'src-1' }),
      );
      expect(
        (await h.commissions.findByPaymentId('pay-1'))?.reviewReasons,
      ).toEqual(['PAID_BY_AGENT', 'PAYMENT_SOURCE_REUSED']);
    });
  });

  describe('the policy', () => {
    it("an agent's own policy beats the active one, and the rule is snapshotted", async () => {
      h.seedPolicy({ id: 'pol-2', version: 2, value: 2000, holdDays: 7 });
      await h.policy.assignToAgent('agent-1', 'pol-1');
      await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
      expect(await h.commissions.findByPaymentId('pay-1')).toMatchObject({
        policyVersionId: 'pol-1',
        ruleValue: 1000,
      });
    });

    it('the active version is used and a later change does not touch the commission', async () => {
      await h.events.onPaymentSucceeded(h.paymentSucceeded(1));
      h.seedPolicy({ id: 'pol-2', version: 2, value: 5000, holdDays: 1 });
      expect(await h.commissions.findByPaymentId('pay-1')).toMatchObject({
        policyVersionId: 'pol-1',
        ruleValue: 1000,
        amountPaise: 805,
      });
    });

    it('with no policy in effect it throws and creates nothing (the event can be retried)', async () => {
      const hh = makeCommissionHarness();
      await hh.seedAgent();
      await hh.seedAttribution(1);
      await expect(
        hh.events.onPaymentSucceeded(hh.paymentSucceeded(1)),
      ).rejects.toBeInstanceOf(AgentCommissionPolicyMissingError);
      expect(await hh.commissions.findByPaymentId('pay-1')).toBeNull();
    });
  });

  it('a failed audit write leaves no commission behind', async () => {
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(
      h.events.onPaymentSucceeded(h.paymentSucceeded(1)),
    ).rejects.toThrow('audit down');
    expect(await h.commissions.findByPaymentId('pay-1')).toBeNull();
  });
});

describe('onPaymentRefunded', () => {
  const approved = async () => {
    const created = await h.seedCommission(1);
    await h.uow.run((tx) =>
      h.approval.approve(
        created,
        new Date(T0.getTime() + 20 * DAY),
        null,
        't',
        tx,
      ),
    );
    return (await h.commissions.findById(created.id))!;
  };

  it('a refund before approval cancels the commission; nothing was credited', async () => {
    await h.seedCommission(1);
    const result = await h.events.onPaymentRefunded(h.paymentRefunded(1, 1));
    expect(result.outcome).toBe('CANCELLED');
    expect(await h.commissions.findByPaymentId('pay-1')).toMatchObject({
      status: 'CANCELLED',
      cancelledAt: new Date(T0.getTime() + 2 * HOUR),
    });
    expect(h.ledger.all).toHaveLength(0);
  });

  it('a replayed pre-approval refund changes nothing more', async () => {
    await h.seedCommission(1);
    await h.events.onPaymentRefunded(h.paymentRefunded(1, 1));
    const auditCount = h.audit.entries.length;
    const again = await h.events.onPaymentRefunded(h.paymentRefunded(1, 1));
    expect(again.outcome).toBe('NOTHING_TO_REVERSE');
    expect(h.audit.entries).toHaveLength(auditCount);
  });

  it('a full refund of an approved commission reverses what was credited', async () => {
    const c = await approved();
    const result = await h.events.onPaymentRefunded(h.paymentRefunded(1, 1));
    expect(result).toMatchObject({ outcome: 'REVERSED', reversalPaise: 805 });
    expect(await h.commissions.findById(c.id)).toMatchObject({
      status: 'REVERSED',
      reversedPaise: 805,
      creditedPaise: 805,
    });
    expect(await h.ledger.balance('agent-1')).toBe(0);
    expect((await h.ledger.findByKey('reversal:rf-1'))?.amountPaise).toBe(-805);
  });

  it('a partial refund reverses a proportional part and keeps the status', async () => {
    const c = await approved();
    const result = await h.events.onPaymentRefunded(
      h.paymentRefunded(1, 1, {
        refundedPaise: 2_375,
        totalRefundedPaise: 2_375,
        fullyRefunded: false,
      }),
    );
    // floor(805 * 2375 / 9500) = 201
    expect(result).toMatchObject({ outcome: 'REVERSED', reversalPaise: 201 });
    expect(await h.commissions.findById(c.id)).toMatchObject({
      status: 'APPROVED',
      reversedPaise: 201,
    });
    expect(await h.ledger.balance('agent-1')).toBe(805 - 201);
  });

  it('several partial refunds and then the full one add up to exactly what was credited', async () => {
    const c = await approved();
    await h.events.onPaymentRefunded(
      h.paymentRefunded(1, 1, {
        refundedPaise: 2_375,
        totalRefundedPaise: 2_375,
        fullyRefunded: false,
      }),
    );
    await h.events.onPaymentRefunded(
      h.paymentRefunded(1, 2, {
        refundedPaise: 2_375,
        totalRefundedPaise: 4_750,
        fullyRefunded: false,
      }),
    );
    // After the second partial refund the total refunded is half the payment,
    // so half of the credit (floor(805 * 4750 / 9500) = 402) is reversed.
    expect((await h.commissions.findById(c.id))?.reversedPaise).toBe(402);
    await h.events.onPaymentRefunded(
      h.paymentRefunded(1, 3, {
        refundedPaise: 4_750,
        totalRefundedPaise: 9_500,
        fullyRefunded: true,
      }),
    );
    expect(await h.commissions.findById(c.id)).toMatchObject({
      status: 'REVERSED',
      reversedPaise: 805,
    });
    expect(await h.ledger.balance('agent-1')).toBe(0);
  });

  it('a replayed refund reverses nothing twice', async () => {
    await approved();
    const event = h.paymentRefunded(1, 1, {
      refundedPaise: 2_375,
      totalRefundedPaise: 2_375,
      fullyRefunded: false,
    });
    await h.events.onPaymentRefunded(event);
    const again = await h.events.onPaymentRefunded(event);
    expect(again.outcome).toBe('ALREADY_PROCESSED');
    expect(await h.ledger.balance('agent-1')).toBe(805 - 201);
    expect(h.ledger.all.filter((e) => e.type === 'REVERSAL')).toHaveLength(1);
  });

  it('a refund after the payout was paid can leave the balance negative', async () => {
    const c = await approved();
    await h.commissions.update(c.id, { status: 'PAID', paidAt: T0 });
    await h.ledger.append({
      agentId: 'agent-1',
      type: 'PAYOUT_DEBIT',
      amountPaise: -805,
      idempotencyKey: 'payout:x',
      commissionId: null,
      refundId: null,
      payoutId: 'x',
      calcType: null,
      value: null,
      ruleSnapshot: null,
      reason: null,
    });
    await h.events.onPaymentRefunded(h.paymentRefunded(1, 1));
    expect(await h.ledger.balance('agent-1')).toBe(-805);
    expect((await h.commissions.findById(c.id))?.status).toBe('REVERSED');
  });

  it('a refund of a payment that earned no commission is ignored', async () => {
    const result = await h.events.onPaymentRefunded(h.paymentRefunded(5, 1));
    expect(result.outcome).toBe('NO_COMMISSION');
  });

  it('a commission that is already closed is left alone', async () => {
    const c = await h.seedCommission(1, { status: 'CANCELLED' });
    const result = await h.events.onPaymentRefunded(h.paymentRefunded(1, 1));
    expect(result.outcome).toBe('NOTHING_TO_REVERSE');
    expect((await h.commissions.findById(c.id))?.status).toBe('CANCELLED');
  });

  it('losing a race on the commission throws so the event is retried', async () => {
    await h.seedCommission(1);
    jest.spyOn(h.commissions, 'transition').mockResolvedValueOnce(null);
    await expect(
      h.events.onPaymentRefunded(h.paymentRefunded(1, 1)),
    ).rejects.toMatchObject({ code: 'CONCURRENT_CHANGE' });
    expect((await h.commissions.findByPaymentId('pay-1'))?.status).toBe(
      'ON_HOLD',
    );
  });

  it('losing a race while reversing throws and leaves the ledger untouched', async () => {
    const c = await approved();
    jest.spyOn(h.commissions, 'transition').mockResolvedValueOnce(null);
    await expect(
      h.events.onPaymentRefunded(
        h.paymentRefunded(1, 1, {
          refundedPaise: 2_375,
          totalRefundedPaise: 2_375,
          fullyRefunded: false,
        }),
      ),
    ).rejects.toMatchObject({ code: 'CONCURRENT_CHANGE' });
    expect(await h.ledger.findByKey('reversal:rf-1')).toBeNull();
    expect((await h.commissions.findById(c.id))?.reversedPaise).toBe(0);
  });

  it('a failed audit write undoes the reversal', async () => {
    const c = await approved();
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(
      h.events.onPaymentRefunded(h.paymentRefunded(1, 1)),
    ).rejects.toThrow('audit down');
    expect(await h.ledger.findByKey('reversal:rf-1')).toBeNull();
    expect((await h.commissions.findById(c.id))?.status).toBe('APPROVED');
  });

  it.each([
    ['refundId', { refundId: '' }],
    ['totalRefundedPaise', { totalRefundedPaise: -5 }],
    ['refundedAt', { refundedAt: 'nope' }],
  ])('refuses an event with a bad %s', async (_field, override) => {
    await expect(
      h.events.onPaymentRefunded(h.paymentRefunded(1, 1, override)),
    ).rejects.toThrow(RangeError);
  });

  it('exposes AgentMoneyError for callers', () => {
    expect(new AgentMoneyError('CONCURRENT_CHANGE').code).toBe(
      'CONCURRENT_CHANGE',
    );
  });
});
