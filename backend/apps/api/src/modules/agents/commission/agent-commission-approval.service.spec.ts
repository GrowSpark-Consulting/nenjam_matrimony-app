import { AgentConfigError } from '../config/agent-config.service';
import type { CommissionRepository } from '../ports/agent-commission-ports';
import {
  DAY,
  HOUR,
  T0,
  makeCommissionHarness,
  type CommissionHarness,
} from '../testing/agent-commission-harness';

let h: CommissionHarness;
const HOLD_END = new Date(T0.getTime() + HOUR + 14 * DAY);
const justBefore = new Date(HOLD_END.getTime() - 1);

beforeEach(() => {
  h = makeCommissionHarness();
  h.seedPolicy();
});

const run = (at: Date, batch = 10) => h.approval.runDailyApproval(at, batch);
const status = async (n = 1) =>
  (await h.commissions.findByPaymentId(`pay-${n}`))?.status;

describe('runDailyApproval', () => {
  it('keeps a commission on hold until the hold ends, and approves it at the boundary', async () => {
    await h.seedCommission(1);
    expect(await run(justBefore)).toMatchObject({ examined: 1, unchanged: 1 });
    expect(await status()).toBe('ON_HOLD');
    expect(await h.ledger.balance('agent-1')).toBe(0);

    // The hold is over when now >= holdUntil.
    expect(await run(HOLD_END)).toMatchObject({ approved: 1 });
    expect(await status()).toBe('APPROVED');
  });

  it('credits the ledger once, with the rule snapshot, and audits it', async () => {
    await h.seedCommission(1);
    await run(HOLD_END);
    const commission = await h.commissions.findByPaymentId('pay-1');
    expect(commission).toMatchObject({
      status: 'APPROVED',
      creditedPaise: 950,
      approvedAt: HOLD_END,
    });
    const credit = await h.ledger.findByKey(`credit:${commission!.id}`);
    expect(credit).toMatchObject({
      type: 'CREDIT',
      amountPaise: 950,
      calcType: 'PERCENTAGE',
      value: 1000,
      ruleSnapshot: {
        calcType: 'PERCENTAGE',
        value: 1000,
        policyVersionId: 'pol-1',
      },
    });
    expect(h.audit.entries.map((e) => e.action)).toContain(
      'COMMISSION_APPROVED',
    );
    expect(await h.ledger.balance('agent-1')).toBe(950);
  });

  it('running it again credits nothing more', async () => {
    await h.seedCommission(1);
    await run(HOLD_END);
    const second = await run(HOLD_END);
    expect(second.examined).toBe(0); // APPROVED is no longer open
    expect(await h.ledger.balance('agent-1')).toBe(950);
    expect(h.ledger.all).toHaveLength(1);
  });

  it('two runs at once credit the commission once', async () => {
    await h.seedCommission(1);
    await Promise.all([run(HOLD_END), run(HOLD_END)]);
    expect(await h.ledger.balance('agent-1')).toBe(950);
    expect(h.ledger.all).toHaveLength(1);
  });

  it('without auto-approve a commission waits for an admin (READY) and stays there', async () => {
    h.settings.set('commission.auto_approve', false);
    await h.seedCommission(1);
    expect(await run(HOLD_END)).toMatchObject({ moved: 1 });
    expect(await status()).toBe('READY');
    expect(await run(new Date(HOLD_END.getTime() + 30 * DAY))).toMatchObject({
      unchanged: 1,
    });
    expect(await status()).toBe('READY');
    expect(h.ledger.all).toHaveLength(0);
  });

  it('a commission in review is left for an admin', async () => {
    await h.seedCommission(1, { status: 'IN_REVIEW' });
    expect(await run(HOLD_END)).toMatchObject({ unchanged: 1 });
    expect(await status()).toBe('IN_REVIEW');
  });

  describe('suspended and terminated agents', () => {
    it.each(['SUSPENDED', 'TERMINATED'] as const)(
      'a %s agent freezes the waiting commission, and nothing is credited',
      async (agentStatus) => {
        await h.seedCommission(1);
        await h.agents.update('agent-1', { status: agentStatus });
        expect(await run(HOLD_END)).toMatchObject({ moved: 1 });
        expect(await status()).toBe('FROZEN');
        expect(h.ledger.all).toHaveLength(0);
      },
    );

    it('a frozen commission is evaluated again once the agent is active', async () => {
      await h.seedCommission(1, { status: 'FROZEN' });
      expect(await run(HOLD_END)).toMatchObject({ approved: 1 });
      expect(await status()).toBe('APPROVED');
    });
  });

  describe('profile verification', () => {
    it('is not consulted when it is not required', async () => {
      await h.seedCommission(1);
      await run(HOLD_END);
      expect(h.profiles.calls).toBe(0);
    });

    it('holds an unverified profile when verification is required, approves once verified', async () => {
      h.settings.set('commission.require_verified_profile', true);
      await h.seedCommission(1);
      expect(await run(HOLD_END)).toMatchObject({ moved: 1 });
      expect(await status()).toBe('AWAITING_VERIFICATION');
      h.profiles.verified.add('member-1');
      expect(await run(HOLD_END)).toMatchObject({ approved: 1 });
      expect(await status()).toBe('APPROVED');
    });
  });

  describe('the commission base', () => {
    it('does nothing while the base is not configured, then fills the amount from the stored values', async () => {
      h.settings.set('commission.base', null);
      await h.seedCommission(1);
      expect(await run(HOLD_END)).toMatchObject({ unchanged: 1 });
      expect(await h.commissions.findByPaymentId('pay-1')).toMatchObject({
        status: 'ON_HOLD',
        amountPaise: null,
      });

      h.settings.set('commission.base', 'AMOUNT_PAID_EXCLUDING_GST');
      expect(await run(HOLD_END)).toMatchObject({ approved: 1 });
      expect(await h.commissions.findByPaymentId('pay-1')).toMatchObject({
        status: 'APPROVED',
        basePaise: 9500,
        amountPaise: 950,
        creditedPaise: 950,
      });
    });

    it('a late-filled amount is capped by what the member paid, GST included', async () => {
      const hh = makeCommissionHarness();
      hh.seedPolicy({ value: 10_000 });
      await hh.seedAgent();
      await hh.seedAttribution(1);
      hh.settings.set('commission.base', null);
      await hh.events.onPaymentSucceeded(hh.paymentSucceeded(1));
      hh.settings.set('commission.base', 'AMOUNT_PAID');
      await hh.approval.runDailyApproval(HOLD_END, 10);
      expect(await hh.commissions.findByPaymentId('pay-1')).toMatchObject({
        status: 'APPROVED',
        amountPaise: 11210,
      });
    });

    it('approves a commission of zero without a ledger entry', async () => {
      await h.seedCommission(1, { amountPaise: 0, basePaise: 0 });
      expect(await run(HOLD_END)).toMatchObject({ approved: 1 });
      expect(h.ledger.all).toHaveLength(0);
      expect(
        (await h.commissions.findByPaymentId('pay-1'))?.creditedPaise,
      ).toBe(0);
    });
  });

  describe('batches and failures', () => {
    it('works through every open commission, a page at a time', async () => {
      for (let n = 1; n <= 5; n++) {
        await h.seedCommission(n);
      }
      const summary = await run(HOLD_END, 2);
      expect(summary).toMatchObject({
        examined: 5,
        approved: 5,
        failedIds: [],
      });
      expect(await h.ledger.balance('agent-1')).toBe(950 * 5);
    });

    it('one failing commission does not stop the others', async () => {
      for (let n = 1; n <= 3; n++) await h.seedCommission(n);
      const badId = (await h.commissions.findByPaymentId('pay-2'))!.id;
      const original = h.commissions.transition.bind(
        h.commissions,
      ) as CommissionRepository['transition'];
      jest
        .spyOn(h.commissions, 'transition')
        .mockImplementation((id, from, changes, tx) =>
          id === badId
            ? Promise.reject(new Error('database hiccup'))
            : original(id, from, changes, tx),
        );
      const summary = await run(HOLD_END, 10);
      expect(summary).toMatchObject({
        examined: 3,
        approved: 2,
        failedIds: [badId],
      });
      expect(await status(2)).toBe('ON_HOLD');
      // The failed one left no credit behind.
      expect(await h.ledger.balance('agent-1')).toBe(950 * 2);
    });

    it('losing a race on a commission counts it as failed, not credited twice', async () => {
      await h.seedCommission(1);
      jest.spyOn(h.commissions, 'transition').mockResolvedValueOnce(null);
      const summary = await run(HOLD_END);
      expect(summary.failedIds).toHaveLength(1);
      expect(h.ledger.all).toHaveLength(0);
    });
  });

  it('refuses when auto-approve is not configured at all', async () => {
    h.settings.remove('commission.auto_approve');
    await expect(run(HOLD_END)).rejects.toBeInstanceOf(AgentConfigError);
  });

  it.each([0, -1, 1.5, Number.NaN])('refuses batch size %s', async (size) => {
    await expect(run(HOLD_END, size)).rejects.toThrow(RangeError);
  });

  it('refuses an invalid date', async () => {
    await expect(run(new Date('nope'))).rejects.toThrow(RangeError);
  });
});

describe('approve (the step the admin service reuses)', () => {
  it('refuses a commission with no amount', async () => {
    h.settings.set('commission.base', null);
    const c = await h.seedCommission(1);
    await expect(
      h.uow.run((tx) => h.approval.approve(c, HOLD_END, 'staff-1', 'ok', tx)),
    ).rejects.toMatchObject({ code: 'COMMISSION_AMOUNT_NOT_SET' });
  });

  it('records who approved it', async () => {
    const c = await h.seedCommission(1);
    await h.uow.run((tx) =>
      h.approval.approve(c, HOLD_END, 'staff-1', 'looks fine', tx),
    );
    expect(
      h.audit.entries.find((e) => e.action === 'COMMISSION_APPROVED'),
    ).toMatchObject({ actorId: 'staff-1', entityId: c.id });
  });

  it('the audit row is written in the same transaction: a failed credit removes it', async () => {
    const c = await h.seedCommission(1);
    const before = h.audit.entries.length;
    jest
      .spyOn(h.ledger, 'append')
      .mockRejectedValueOnce(new Error('ledger down'));
    await expect(
      h.uow.run((tx) => h.approval.approve(c, HOLD_END, null, 'x', tx)),
    ).rejects.toThrow('ledger down');
    expect(h.audit.entries).toHaveLength(before);
    expect((await h.commissions.findById(c.id))?.status).toBe('ON_HOLD');
  });

  it('a failed audit write undoes the approval and the credit', async () => {
    const c = await h.seedCommission(1);
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(
      h.uow.run((tx) => h.approval.approve(c, HOLD_END, null, 'x', tx)),
    ).rejects.toThrow('audit down');
    expect((await h.commissions.findById(c.id))?.status).toBe('ON_HOLD');
    expect(h.ledger.all).toHaveLength(0);
  });
});
