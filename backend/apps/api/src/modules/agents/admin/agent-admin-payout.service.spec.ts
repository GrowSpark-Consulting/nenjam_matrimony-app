import {
  AgentPermissionDeniedError,
  type AgentAuditPort,
} from '../ports/agent-platform-ports';
import {
  NOBODY,
  PARTNER,
  PAYER,
  SUPER,
  actorOf,
  makeAdminHarness,
  type AdminHarness,
} from '../testing/agent-admin-harness';
import { DAY, HOUR, T0 } from '../testing/agent-commission-harness';

let h: AdminHarness;
const payer = actorOf(PAYER);
const REASON = 'monthly payout';
const HOLD_END = new Date(T0.getTime() + HOUR + 14 * DAY);
const PAYOUT_DAY = new Date(HOLD_END.getTime() + 10 * DAY);
const DESTINATION = { upi: { vpa: 'ravi@okbank' } };
const disclosures = () =>
  h.audit.entries.filter((e) => e.action === 'payout.destination.disclose');

async function readyPayout(n = 1, amount = 60_000) {
  await h.seedAttribution(n);
  const c = await h.commissions.create({
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
  await h.uow.run((tx) => h.approval.approve(c, HOLD_END, null, 'seed', tx));
}

beforeEach(async () => {
  h = makeAdminHarness();
  h.seedPolicy();
  await h.seedAgent('ACTIVE', { id: 'agent-1', name: 'Ravi Kumar' });
  await h.agents.update('agent-1', {
    panLast4: '234F',
    panSealed: 'x',
    panVerifiedAt: T0,
  });
  await h.seedPayoutDetails('agent-1', T0);
  await h.codes.create({
    id: 'code-1',
    agentId: 'agent-1',
    code: 'NM7K2P9X',
    isPrimary: true,
    isActive: true,
    createdAt: T0,
  });
  h.clock.set(PAYOUT_DAY);
});

const create = (actor = payer, period = '2026-11') =>
  h.payoutsAdmin.create(actor, { agentId: 'agent-1', period, reason: REASON });

describe('permissions', () => {
  const calls: Array<
    [string, (a: ReturnType<typeof actorOf>) => Promise<unknown>]
  > = [
    ['list', (a) => h.payoutsAdmin.list(a)],
    ['get', (a) => h.payoutsAdmin.get(a, 'x')],
    ['create', (a) => create(a)],
    [
      'markPaid',
      (a) =>
        h.payoutsAdmin.markPaid(a, 'x', {
          reference: 'R',
          paidAt: T0,
          reason: REASON,
        }),
    ],
    ['cancel', (a) => h.payoutsAdmin.cancel(a, 'x', REASON)],
  ];

  it.each(calls)(
    '%s is refused to a partner manager and to anyone without payout permissions',
    async (_name, call) => {
      for (const user of [PARTNER, NOBODY]) {
        await expect(call(actorOf(user))).rejects.toBeInstanceOf(
          AgentPermissionDeniedError,
        );
      }
      expect(h.audit.entries).toHaveLength(0);
    },
  );

  it('create, mark-paid and cancel need a fresh step-up; the permission is checked first', async () => {
    await readyPayout();
    await expect(create(actorOf(PAYER, false))).rejects.toMatchObject({
      code: 'ADMIN_STEP_UP_REQUIRED',
    });
    await expect(create(actorOf(NOBODY, false))).rejects.toBeInstanceOf(
      AgentPermissionDeniedError,
    );
    await expect(
      h.payoutsAdmin.cancel(actorOf(PAYER, false), 'x', REASON),
    ).rejects.toMatchObject({ code: 'ADMIN_STEP_UP_REQUIRED' });
    expect(
      await h.payouts.findActiveByAgentPeriod('agent-1', '2026-11'),
    ).toBeNull();
    expect(
      h.audit.entries.filter((e) => e.action === 'payout.create'),
    ).toHaveLength(0);
  });
});

describe('create', () => {
  it('returns the payout with the payee and the destination, and audits the disclosure', async () => {
    await readyPayout();
    const { payout, created } = await create();
    expect(created).toBe(true);
    expect(payout).toMatchObject({
      agentName: 'Ravi Kumar',
      agentCode: 'NM7K2P9X',
      amountPaise: 60_000,
      status: 'CREATED',
      destination: DESTINATION,
    });
    expect(disclosures()).toHaveLength(1);
    expect(disclosures()[0]).toMatchObject({
      actorId: PAYER,
      entityId: payout.id,
      metadata: { payoutId: payout.id, method: 'UPI' },
    });
    expect(JSON.stringify(h.audit.entries)).not.toContain('ravi@okbank');
  });

  it('a repeat returns the same payout (created: false) and discloses again, audited', async () => {
    await readyPayout();
    const first = await create();
    const second = await create();
    expect(second.created).toBe(false);
    expect(second.payout.id).toBe(first.payout.id);
    expect(second.payout.destination).toEqual(DESTINATION);
    expect(disclosures()).toHaveLength(2);
    expect(
      h.audit.entries.filter((e) => e.action === 'payout.create'),
    ).toHaveLength(1);
  });

  it('a lost race at the database is answered with the payout that won', async () => {
    await readyPayout();
    const winner = await create();
    jest
      .spyOn(h.payouts, 'findActiveByAgentPeriod')
      .mockResolvedValueOnce(null);
    // The service then tries to create and the one-payout rule refuses.
    // Make the eligibility see a payable commission again for this attempt.
    jest
      .spyOn(h.commissions, 'listPayableByAgent')
      .mockResolvedValueOnce([(await h.commissions.findById('com-1'))!]);
    jest.spyOn(h.ledger, 'balance').mockResolvedValueOnce(60_000);
    const result = await create();
    expect(result.created).toBe(false);
    expect(result.payout.id).toBe(winner.payout.id);
  });

  it('the disclosure audit row is written in the same transaction: a later failure removes it', async () => {
    await readyPayout();
    const before = h.audit.entries.length;
    // The answer is built after the disclosure is audited; make that step fail.
    jest
      .spyOn(h.codes, 'listByAgent')
      .mockRejectedValueOnce(new Error('lookup down'));
    await expect(create()).rejects.toThrow('lookup down');
    expect(h.audit.entries).toHaveLength(before);
    expect(disclosures()).toHaveLength(0);
  });

  it('refuses an ineligible payout with every reason', async () => {
    await readyPayout();
    await h.agents.update('agent-1', { panVerifiedAt: null });
    await expect(create()).rejects.toMatchObject({
      code: 'PAYOUT_NOT_ELIGIBLE',
      reasons: ['PAN_NOT_VERIFIED'],
    });
    expect(disclosures()).toHaveLength(0);
  });

  it('a failure after the disclosure was audited removes the audit row and the payout', async () => {
    await readyPayout();
    const before = h.audit.entries.length;
    // Fail the disclosure audit write itself: nothing may be returned.
    const original = h.audit.record.bind(h.audit) as AgentAuditPort['record'];
    jest
      .spyOn(h.audit, 'record')
      .mockImplementation((entry, tx) =>
        entry.action === 'payout.destination.disclose'
          ? Promise.reject(new Error('audit down'))
          : original(entry, tx),
      );
    await expect(create()).rejects.toThrow('audit down');
    expect(h.audit.entries).toHaveLength(before);
    expect(
      await h.payouts.findActiveByAgentPeriod('agent-1', '2026-11'),
    ).toBeNull();
    expect(await h.ledger.balance('agent-1')).toBe(60_000);
  });
});

describe('get', () => {
  const existing = async () => {
    await readyPayout();
    const { payout } = await create();
    return payout;
  };

  it('the payer with a fresh step-up gets the destination, audited, without a PAN', async () => {
    const payout = await existing();
    const before = disclosures().length;
    const detail = await h.payoutsAdmin.get(payer, payout.id);
    expect(detail.destination).toEqual(DESTINATION);
    expect(detail).toMatchObject({
      agentName: 'Ravi Kumar',
      agentCode: 'NM7K2P9X',
    });
    expect(detail.commissions).toHaveLength(1);
    expect(disclosures()).toHaveLength(before + 1);
    expect(JSON.stringify(detail)).not.toContain('ABCDE1234F');
  });

  it('without a fresh step-up the field is left out, the answer is still given, and nothing is audited', async () => {
    const payout = await existing();
    const before = h.audit.entries.length;
    const detail = await h.payoutsAdmin.get(actorOf(PAYER, false), payout.id);
    expect('destination' in detail).toBe(false);
    expect(detail.id).toBe(payout.id);
    expect(h.audit.entries).toHaveLength(before);
  });

  it('someone who holds only payout.view never gets the destination, even with a step-up', async () => {
    const payout = await existing();
    h.permission.grant('staff-viewer', { module: 'payout', action: 'view' });
    const before = h.audit.entries.length;
    const detail = await h.payoutsAdmin.get(
      actorOf('staff-viewer', true),
      payout.id,
    );
    expect('destination' in detail).toBe(false);
    expect(h.audit.entries).toHaveLength(before);
    expect(JSON.stringify(detail)).not.toContain('ravi@okbank');
  });

  it('a super admin (who holds payout.execute) gets it with a step-up', async () => {
    const payout = await existing();
    const detail = await h.payoutsAdmin.get(actorOf(SUPER, true), payout.id);
    expect(detail.destination).toEqual(DESTINATION);
  });

  it('fails closed: if the disclosure audit write fails nothing is returned', async () => {
    const payout = await existing();
    const original = h.audit.record.bind(h.audit) as AgentAuditPort['record'];
    jest
      .spyOn(h.audit, 'record')
      .mockImplementation((entry, tx) =>
        entry.action === 'payout.destination.disclose'
          ? Promise.reject(new Error('audit down'))
          : original(entry, tx),
      );
    await expect(h.payoutsAdmin.get(payer, payout.id)).rejects.toThrow(
      'audit down',
    );
  });

  it('an unknown payout is PAYOUT_NOT_FOUND', async () => {
    await expect(h.payoutsAdmin.get(payer, 'nope')).rejects.toMatchObject({
      code: 'PAYOUT_NOT_FOUND',
    });
  });

  it('an agent with no payout details gives no destination and no disclosure row', async () => {
    const payout = await existing();
    const before = h.audit.entries.length;
    await h.payoutDetails.save({
      agentId: 'agent-1',
      method: 'UPI',
      detailsSealed: 'x',
      display: 'd',
      verifiedAt: null,
      changedAt: T0,
    });
    // Details exist but unreadable would throw; use a missing record instead.
    (h.payoutDetails as unknown as { rows: Map<string, unknown> }).rows.delete(
      'agent-1',
    );
    const detail = await h.payoutsAdmin.get(payer, payout.id);
    expect('destination' in detail).toBe(false);
    expect(h.audit.entries).toHaveLength(before);
  });
});

describe('list', () => {
  it('carries the payee on every row and never a destination', async () => {
    await readyPayout();
    await create();
    const page = await h.payoutsAdmin.list(payer);
    expect(page.items).toHaveLength(1);
    expect(page.items[0]).toMatchObject({
      agentName: 'Ravi Kumar',
      agentCode: 'NM7K2P9X',
    });
    expect('destination' in page.items[0]).toBe(false);
    expect(JSON.stringify(page)).not.toContain('ravi@okbank');
    expect(
      (await h.payoutsAdmin.list(payer, { status: 'PAID' })).items,
    ).toHaveLength(0);
    expect(
      (await h.payoutsAdmin.list(payer, { period: '2026-11' })).items,
    ).toHaveLength(1);
  });

  it('the payer has no agent.view but sees the payee name and code here', async () => {
    await readyPayout();
    await create();
    await expect(h.agentsAdmin.list(payer)).rejects.toBeInstanceOf(
      AgentPermissionDeniedError,
    );
    expect((await h.payoutsAdmin.list(payer)).items[0].agentName).toBe(
      'Ravi Kumar',
    );
  });
});

describe('markPaid and cancel', () => {
  const made = async () => {
    await readyPayout();
    return (await create()).payout;
  };
  const paidAt = new Date(PAYOUT_DAY.getTime() - HOUR);

  it('mark-paid answers with the payee and no destination', async () => {
    const payout = await made();
    const result = await h.payoutsAdmin.markPaid(payer, payout.id, {
      reference: 'UTR0001',
      paidAt,
      reason: 'paid by UPI',
    });
    expect(result).toMatchObject({
      status: 'PAID',
      agentName: 'Ravi Kumar',
      agentCode: 'NM7K2P9X',
    });
    expect('destination' in result).toBe(false);
  });

  it('is repeatable with the same reference and refuses a different one', async () => {
    const payout = await made();
    const pay = (reference: string) =>
      h.payoutsAdmin.markPaid(payer, payout.id, {
        reference,
        paidAt,
        reason: 'paid',
      });
    await pay('UTR0001');
    await expect(pay('UTR0001')).resolves.toMatchObject({ status: 'PAID' });
    await expect(pay('UTR9999')).rejects.toMatchObject({
      code: 'PAYOUT_STATUS_NOT_ALLOWED',
    });
  });

  it('cancel answers with the payee, releases the debit and has no destination', async () => {
    const payout = await made();
    const result = await h.payoutsAdmin.cancel(
      payer,
      payout.id,
      'wrong account',
    );
    expect(result).toMatchObject({
      status: 'CANCELLED',
      agentCode: 'NM7K2P9X',
    });
    expect('destination' in result).toBe(false);
    expect(await h.ledger.balance('agent-1')).toBe(60_000);
  });

  it('the permission check and the change share one transaction', async () => {
    const payout = await made();
    const before = h.audit.entries.length;
    jest
      .spyOn(h.ledger, 'append')
      .mockRejectedValueOnce(new Error('ledger down'));
    await expect(
      h.payoutsAdmin.cancel(payer, payout.id, 'wrong account'),
    ).rejects.toThrow('ledger down');
    expect(h.audit.entries).toHaveLength(before);
    expect((await h.payouts.findById(payout.id))?.status).toBe('CREATED');
  });

  it('refuses a missing reason and an unknown payout', async () => {
    const payout = await made();
    await expect(
      h.payoutsAdmin.cancel(payer, payout.id, ''),
    ).rejects.toMatchObject({
      code: 'VALIDATION_FAILED',
    });
    await expect(
      h.payoutsAdmin.cancel(payer, 'nope', REASON),
    ).rejects.toMatchObject({
      code: 'PAYOUT_NOT_FOUND',
    });
  });
});
