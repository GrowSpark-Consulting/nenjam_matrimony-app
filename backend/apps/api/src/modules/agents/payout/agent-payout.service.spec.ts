import { AgentConfigError } from '../config/agent-config.service';
import {
  DAY,
  HOUR,
  T0,
  makeCommissionHarness,
  type CommissionHarness,
} from '../testing/agent-commission-harness';

let h: CommissionHarness;
const HOLD_END = new Date(T0.getTime() + HOUR + 14 * DAY);
const PAYOUT_DAY = new Date(HOLD_END.getTime() + 10 * DAY);

/** An approved commission of `amount` paise (the minimum payout is 50 000). */
async function approvedCommission(n: number, amount: number) {
  await h.seedAttribution(n);
  const created = await h.commissions.create({
    id: `com-${n}`,
    agentId: 'agent-1',
    attributionId: `attr-${n}`,
    paymentId: `pay-${n}`,
    phoneHash: `v1:member-hash-${n}`,
    policyVersionId: 'pol-1',
    status: 'ON_HOLD',
    calcType: 'PERCENTAGE',
    ruleValue: 1000,
    basePaise: amount * 10,
    amountPaise: amount,
    amountPaidPaise: amount * 12,
    taxableAmountPaise: amount * 10,
    refundedPaise: 0,
    preRefundAmountPaise: null,
    creditedPaise: 0,
    reversedPaise: 0,
    holdUntil: HOLD_END,
    reviewReasons: [],
    approvedAt: null,
    paidAt: null,
    cancelledAt: null,
    payoutId: null,
    createdAt: T0,
  });
  await h.uow.run((tx) =>
    h.approval.approve(created, HOLD_END, null, 'seed', tx),
  );
  return (await h.commissions.findById(created.id))!;
}

async function readyAgent() {
  await h.agents.update('agent-1', {
    panLast4: '234F',
    panSealed: 'v1:sealed',
    panVerifiedAt: T0,
  });
  await h.payoutDetails.save({
    agentId: 'agent-1',
    method: 'UPI',
    detailsSealed: 'v1:sealed',
    display: 'r***@okbank',
    verifiedAt: T0,
    changedAt: T0,
  });
}

beforeEach(async () => {
  h = makeCommissionHarness();
  h.seedPolicy();
  await h.seedAgent();
  h.clock.set(PAYOUT_DAY);
});

const create = (period = '2026-11', actorId = 'staff-1') =>
  h.payoutService.create({
    agentId: 'agent-1',
    period,
    actorId,
    reason: 'monthly payout',
  });

describe('create', () => {
  it('pays out the approved commissions, sets them aside in the ledger and audits it', async () => {
    const c1 = await approvedCommission(1, 40_000);
    const c2 = await approvedCommission(2, 30_000);
    await readyAgent();
    const { payout, created } = await create();
    expect(created).toBe(true);
    expect(payout).toMatchObject({
      agentId: 'agent-1',
      period: '2026-11',
      amountPaise: 70_000,
      taxWithheldPaise: 0,
      netPaise: 70_000,
      status: 'CREATED',
      createdBy: 'staff-1',
    });
    expect((await h.commissions.findById(c1.id))?.payoutId).toBe(payout.id);
    expect((await h.commissions.findById(c2.id))?.payoutId).toBe(payout.id);
    expect(await h.ledger.balance('agent-1')).toBe(0);
    expect((await h.ledger.findByKey(`payout:${payout.id}`))?.amountPaise).toBe(
      -70_000,
    );
    expect(h.audit.entries.at(-1)).toMatchObject({
      actorId: 'staff-1',
      action: 'payout.create',
      entityId: payout.id,
    });
  });

  it('is idempotent by agent and period: the second call returns the same payout and changes nothing', async () => {
    await approvedCommission(1, 60_000);
    await readyAgent();
    const first = await create();
    const auditCount = h.audit.entries.length;
    const second = await create();
    expect(second.created).toBe(false);
    expect(second.payout.id).toBe(first.payout.id);
    expect(h.audit.entries).toHaveLength(auditCount);
    expect(h.ledger.all.filter((e) => e.type === 'PAYOUT_DEBIT')).toHaveLength(
      1,
    );
  });

  it('two requests at once make one payout (the one-payout rule decides)', async () => {
    await approvedCommission(1, 60_000);
    await readyAgent();
    const [a, b] = await Promise.all([create(), create()]);
    expect(a.payout.id).toBe(b.payout.id);
    expect([a.created, b.created].sort()).toEqual([false, true]);
    expect(h.ledger.all.filter((e) => e.type === 'PAYOUT_DEBIT')).toHaveLength(
      1,
    );
  });

  it('a lost race at the database answers with the payout that won', async () => {
    await approvedCommission(1, 60_000);
    await readyAgent();
    // The winner's payout exists, but this request does not see it inside its
    // own transaction; the database then refuses the second insert (the
    // one-payout rule) and the answer is the payout that won.
    const winner = await h.payouts.create({
      id: 'winner',
      agentId: 'agent-1',
      period: '2026-11',
      amountPaise: 60_000,
      taxWithheldPaise: 0,
      netPaise: 60_000,
      status: 'CREATED',
      reference: null,
      paidAt: null,
      cancelReason: null,
      cancelledAt: null,
      createdBy: 'staff-2',
      createdAt: T0,
    });
    jest
      .spyOn(h.payouts, 'findActiveByAgentPeriod')
      .mockResolvedValueOnce(null);
    const result = await create();
    expect(result.created).toBe(false);
    expect(result.payout.id).toBe(winner.id);
    expect((await h.commissions.findByPaymentId('pay-1'))?.payoutId).toBeNull();
    expect(h.ledger.all.filter((e) => e.type === 'PAYOUT_DEBIT')).toHaveLength(
      0,
    );
  });

  describe('eligibility', () => {
    const reasonsOf = async () => {
      try {
        await create();
      } catch (error) {
        return (error as { reasons?: string[] }).reasons;
      }
      return undefined;
    };

    it('lists every reason at once', async () => {
      await approvedCommission(1, 10_000); // below the minimum
      // No verified PAN, no verified details.
      expect(await reasonsOf()).toEqual([
        'PAN_NOT_VERIFIED',
        'DETAILS_NOT_VERIFIED',
        'BELOW_MINIMUM',
      ]);
    });

    it('waits after a change of payout details', async () => {
      await approvedCommission(1, 60_000);
      await readyAgent();
      await h.payoutDetails.save({
        agentId: 'agent-1',
        method: 'UPI',
        detailsSealed: 'v1:sealed',
        display: 'r***@okbank',
        verifiedAt: T0,
        changedAt: new Date(PAYOUT_DAY.getTime() - 71 * HOUR),
      });
      expect(await reasonsOf()).toEqual(['WAIT_NOT_OVER']);
      h.clock.advance(HOUR);
      expect((await create()).created).toBe(true);
    });

    it.each(['SUSPENDED', 'PENDING_APPROVAL', 'REJECTED'] as const)(
      'a %s agent cannot be paid',
      async (agentStatus) => {
        await approvedCommission(1, 60_000);
        await readyAgent();
        await h.agents.update('agent-1', { status: agentStatus });
        expect(await reasonsOf()).toEqual(['AGENT_NOT_PAYABLE']);
      },
    );

    it('a terminated agent is still paid what was approved', async () => {
      await approvedCommission(1, 60_000);
      await readyAgent();
      await h.agents.update('agent-1', { status: 'TERMINATED' });
      expect((await create()).created).toBe(true);
    });

    it('refuses when there is nothing to pay', async () => {
      await readyAgent();
      expect(await reasonsOf()).toEqual(['NOTHING_TO_PAY', 'BELOW_MINIMUM']);
    });

    it('refuses a tax rule the CA has not defined yet', async () => {
      h.settings.set('payout.tax_withholding', { rate: 10 });
      await approvedCommission(1, 60_000);
      await readyAgent();
      expect(await reasonsOf()).toEqual(['TAX_RULE_UNSUPPORTED']);
    });

    it('refuses when the ledger cannot cover the payout (an earlier clawback)', async () => {
      const c = await approvedCommission(1, 60_000);
      await readyAgent();
      await h.ledger.append({
        agentId: 'agent-1',
        type: 'ADJUSTMENT',
        amountPaise: -20_000,
        idempotencyKey: 'adj:1',
        commissionId: c.id,
        refundId: null,
        payoutId: null,
        calcType: null,
        value: null,
        ruleSnapshot: null,
        reason: 'clawback',
      });
      expect(await reasonsOf()).toEqual(['LEDGER_BALANCE_TOO_LOW']);
    });

    it('a reversal reduces what the commission pays out', async () => {
      const c = await approvedCommission(1, 60_000);
      await readyAgent();
      await h.events.onPaymentRefunded(
        h.paymentRefunded(1, 1, {
          totalRefundedPaise: 36_000,
          refundedPaise: 36_000,
          fullyRefunded: false,
        }),
      );
      const reversed = (await h.commissions.findById(c.id))!.reversedPaise;
      expect(reversed).toBeGreaterThan(0);
      const { payout } = await create();
      expect(payout.amountPaise).toBe(60_000 - reversed);
    });
  });

  it('refuses a missing minimum or wait setting', async () => {
    await approvedCommission(1, 60_000);
    h.settings.remove('payout.minimum_amount_paise');
    await expect(create()).rejects.toBeInstanceOf(AgentConfigError);
  });

  it('an unknown agent is refused', async () => {
    await expect(
      h.payoutService.create({
        agentId: 'nobody',
        period: '2026-11',
        actorId: 'staff-1',
        reason: 'monthly payout',
      }),
    ).rejects.toMatchObject({ code: 'AGENT_NOT_FOUND' });
  });

  it.each([
    ['reason', { reason: 'no' }],
    ['actorId', { actorId: '' }],
    ['agentId', { agentId: ' ' }],
  ])('needs a valid %s', async (field, override) => {
    await expect(
      h.payoutService.create({
        agentId: 'agent-1',
        period: '2026-11',
        actorId: 'staff-1',
        reason: 'monthly payout',
        ...override,
      }),
    ).rejects.toMatchObject({ code: 'VALIDATION_FAILED', fields: [field] });
  });

  it('a failed audit write leaves no payout, no attachment and no ledger debit', async () => {
    const c = await approvedCommission(1, 60_000);
    await readyAgent();
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(create()).rejects.toThrow('audit down');
    expect(
      await h.payouts.findActiveByAgentPeriod('agent-1', '2026-11'),
    ).toBeNull();
    expect((await h.commissions.findById(c.id))?.payoutId).toBeNull();
    expect(await h.ledger.balance('agent-1')).toBe(60_000);
  });

  it('the audit row is written in the same transaction: a later failure removes it', async () => {
    await approvedCommission(1, 60_000);
    await readyAgent();
    const before = h.audit.entries.length;
    jest
      .spyOn(h.ledger, 'append')
      .mockRejectedValueOnce(new Error('ledger down'));
    await expect(create()).rejects.toThrow('ledger down');
    expect(h.audit.entries).toHaveLength(before);
    expect(
      await h.payouts.findActiveByAgentPeriod('agent-1', '2026-11'),
    ).toBeNull();
  });

  it('if an attachment is lost the whole payout is undone', async () => {
    const c = await approvedCommission(1, 60_000);
    await readyAgent();
    jest.spyOn(h.commissions, 'attachToPayout').mockResolvedValueOnce(0);
    await expect(create()).rejects.toMatchObject({ code: 'CONCURRENT_CHANGE' });
    expect(
      await h.payouts.findActiveByAgentPeriod('agent-1', '2026-11'),
    ).toBeNull();
    expect((await h.commissions.findById(c.id))?.payoutId).toBeNull();
    expect(await h.ledger.balance('agent-1')).toBe(60_000);
  });
});

describe('markPaid', () => {
  const setup = async () => {
    const c = await approvedCommission(1, 60_000);
    await readyAgent();
    const { payout } = await create();
    return { c, payout };
  };
  const paid = (payoutId: string, reference = 'UTR0001', o = {}) =>
    h.payoutService.markPaid({
      payoutId,
      reference,
      paidAt: new Date(PAYOUT_DAY.getTime() - HOUR),
      actorId: 'staff-1',
      reason: 'paid by UPI',
      ...o,
    });

  it('marks the payout and its commissions paid and audits it', async () => {
    const { c, payout } = await setup();
    const result = await paid(payout.id);
    expect(result).toMatchObject({ status: 'PAID', reference: 'UTR0001' });
    expect(await h.commissions.findById(c.id)).toMatchObject({
      status: 'PAID',
    });
    expect(h.audit.entries.at(-1)).toMatchObject({
      action: 'payout.mark_paid',
    });
  });

  it('is idempotent by reference: the same reference again changes nothing', async () => {
    const { payout } = await setup();
    await paid(payout.id);
    const auditCount = h.audit.entries.length;
    const again = await paid(payout.id);
    expect(again.status).toBe('PAID');
    expect(h.audit.entries).toHaveLength(auditCount);
  });

  it('a different reference on a paid payout is refused', async () => {
    const { payout } = await setup();
    await paid(payout.id);
    await expect(paid(payout.id, 'UTR9999')).rejects.toMatchObject({
      code: 'PAYOUT_STATUS_NOT_ALLOWED',
    });
    expect((await h.payouts.findById(payout.id))?.reference).toBe('UTR0001');
  });

  it('two requests at once with the same reference pay it once', async () => {
    const { payout } = await setup();
    const [a, b] = await Promise.all([paid(payout.id), paid(payout.id)]);
    expect(a.status).toBe('PAID');
    expect(b.status).toBe('PAID');
    expect(
      h.audit.entries.filter((e) => e.action === 'payout.mark_paid'),
    ).toHaveLength(1);
  });

  it('a reference already used by another payout is refused', async () => {
    const { payout } = await setup();
    await paid(payout.id, 'UTR0001');
    await approvedCommission(2, 60_000);
    const second = (await create('2026-12')).payout;
    await expect(paid(second.id, 'UTR0001')).rejects.toMatchObject({
      code: 'REFERENCE_ALREADY_USED',
    });
    expect((await h.payouts.findById(second.id))?.status).toBe('CREATED');
  });

  it('refuses a paid-at time in the future', async () => {
    const { payout } = await setup();
    await expect(
      paid(payout.id, 'UTR0001', {
        paidAt: new Date(PAYOUT_DAY.getTime() + HOUR),
      }),
    ).rejects.toMatchObject({ code: 'VALIDATION_FAILED', fields: ['paidAt'] });
  });

  it('refuses an unknown payout and a cancelled one', async () => {
    const { payout } = await setup();
    await expect(paid('nope')).rejects.toMatchObject({
      code: 'PAYOUT_NOT_FOUND',
    });
    await h.payoutService.cancel({
      payoutId: payout.id,
      actorId: 'staff-1',
      reason: 'wrong account',
    });
    await expect(paid(payout.id)).rejects.toMatchObject({
      code: 'PAYOUT_STATUS_NOT_ALLOWED',
    });
  });

  it('needs a reference and a reason', async () => {
    const { payout } = await setup();
    await expect(paid(payout.id, ' ')).rejects.toMatchObject({
      fields: ['reference'],
    });
    await expect(paid(payout.id, 'UTR1', { reason: '' })).rejects.toMatchObject(
      {
        fields: ['reason'],
      },
    );
  });

  it('the audit row is written in the same transaction: a later failure removes it', async () => {
    const { c, payout } = await setup();
    const before = h.audit.entries.length;
    jest
      .spyOn(h.commissions, 'markPaidForPayout')
      .mockRejectedValueOnce(new Error('commissions down'));
    await expect(paid(payout.id)).rejects.toThrow('commissions down');
    expect(h.audit.entries).toHaveLength(before);
    expect((await h.payouts.findById(payout.id))?.status).toBe('CREATED');
    expect((await h.commissions.findById(c.id))?.status).toBe('APPROVED');
  });

  it('a failed audit write leaves the payout unpaid', async () => {
    const { c, payout } = await setup();
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(paid(payout.id)).rejects.toThrow('audit down');
    expect((await h.payouts.findById(payout.id))?.status).toBe('CREATED');
    expect((await h.commissions.findById(c.id))?.status).toBe('APPROVED');
  });
});

describe('cancel', () => {
  const setup = async () => {
    const c = await approvedCommission(1, 60_000);
    await readyAgent();
    const { payout } = await create();
    return { c, payout };
  };
  const cancel = (payoutId: string, reason = 'wrong account') =>
    h.payoutService.cancel({ payoutId, actorId: 'staff-1', reason });

  it('releases the ledger debit and frees the commissions and the period', async () => {
    const { c, payout } = await setup();
    expect(await h.ledger.balance('agent-1')).toBe(0);
    const cancelled = await cancel(payout.id);
    expect(cancelled).toMatchObject({
      status: 'CANCELLED',
      cancelReason: 'wrong account',
    });
    expect((await h.commissions.findById(c.id))?.payoutId).toBeNull();
    expect(await h.ledger.balance('agent-1')).toBe(60_000);
    expect(
      (await h.ledger.findByKey(`payout-release:${payout.id}`))?.amountPaise,
    ).toBe(60_000);
    // The period is free again.
    const again = await create();
    expect(again.created).toBe(true);
    expect(again.payout.id).not.toBe(payout.id);
  });

  it('is idempotent: a cancelled payout stays as it is and releases nothing twice', async () => {
    const { payout } = await setup();
    await cancel(payout.id);
    const auditCount = h.audit.entries.length;
    await cancel(payout.id);
    expect(h.audit.entries).toHaveLength(auditCount);
    expect(
      h.ledger.all.filter((e) => e.type === 'PAYOUT_RELEASE'),
    ).toHaveLength(1);
    expect(await h.ledger.balance('agent-1')).toBe(60_000);
  });

  it('a paid payout cannot be cancelled', async () => {
    const { payout } = await setup();
    await h.payoutService.markPaid({
      payoutId: payout.id,
      reference: 'UTR0001',
      paidAt: new Date(PAYOUT_DAY.getTime() - HOUR),
      actorId: 'staff-1',
      reason: 'paid',
    });
    await expect(cancel(payout.id)).rejects.toMatchObject({
      code: 'PAYOUT_STATUS_NOT_ALLOWED',
    });
    expect(await h.ledger.balance('agent-1')).toBe(0);
  });

  it('refuses an unknown payout and a missing reason', async () => {
    const { payout } = await setup();
    await expect(cancel('nope')).rejects.toMatchObject({
      code: 'PAYOUT_NOT_FOUND',
    });
    await expect(cancel(payout.id, '')).rejects.toMatchObject({
      code: 'VALIDATION_FAILED',
    });
  });

  it('the audit row is written in the same transaction: a later failure removes it', async () => {
    const { payout } = await setup();
    const before = h.audit.entries.length;
    jest
      .spyOn(h.ledger, 'append')
      .mockRejectedValueOnce(new Error('ledger down'));
    await expect(cancel(payout.id)).rejects.toThrow('ledger down');
    expect(h.audit.entries).toHaveLength(before);
    expect((await h.payouts.findById(payout.id))?.status).toBe('CREATED');
    expect(await h.ledger.balance('agent-1')).toBe(0);
  });

  it('a failed audit write leaves the payout and the debit in place', async () => {
    const { c, payout } = await setup();
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(cancel(payout.id)).rejects.toThrow('audit down');
    expect((await h.payouts.findById(payout.id))?.status).toBe('CREATED');
    expect((await h.commissions.findById(c.id))?.payoutId).toBe(payout.id);
    expect(await h.ledger.balance('agent-1')).toBe(0);
  });
});
