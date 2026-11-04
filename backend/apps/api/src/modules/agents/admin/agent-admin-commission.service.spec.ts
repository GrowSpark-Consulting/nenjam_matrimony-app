import { AgentPermissionDeniedError } from '../ports/agent-platform-ports';
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
const super_ = actorOf(SUPER);
const REASON = 'goodwill after a complaint';
const LATE = new Date(T0.getTime() + HOUR + 20 * DAY);

beforeEach(async () => {
  h = makeAdminHarness();
  h.seedPolicy();
  await h.seedAgent();
});

const make = async (
  n = 1,
  status: Parameters<typeof h.commissions.update>[1]['status'] = 'READY',
) => {
  const c = await h.seedCommission(n);
  return h.commissions.update(c.id, { status });
};

describe('permissions', () => {
  it.each([
    ['list', (a: ReturnType<typeof actorOf>) => h.commissionsAdmin.list(a)],
    [
      'approve',
      (a: ReturnType<typeof actorOf>) =>
        h.commissionsAdmin.approve(a, 'x', REASON),
    ],
    [
      'cancel',
      (a: ReturnType<typeof actorOf>) =>
        h.commissionsAdmin.cancel(a, 'x', REASON),
    ],
    [
      'override',
      (a: ReturnType<typeof actorOf>) =>
        h.commissionsAdmin.override(a, 'x', 1, REASON),
    ],
  ])(
    '%s is refused to the payer, a partner manager and anyone else',
    async (_name, call) => {
      for (const user of [PAYER, PARTNER, NOBODY]) {
        await expect(call(actorOf(user))).rejects.toBeInstanceOf(
          AgentPermissionDeniedError,
        );
      }
      expect(
        h.audit.entries.filter((e) => e.action.startsWith('commission.')),
      ).toHaveLength(0);
    },
  );
});

describe('list', () => {
  it('shows the internal and the public status, newest first, with filters', async () => {
    await make(1, 'IN_REVIEW');
    await make(2, 'FROZEN');
    const page = await h.commissionsAdmin.list(super_);
    expect(page.items.map((i) => [i.status, i.publicStatus])).toEqual([
      ['FROZEN', 'ON_HOLD'],
      ['IN_REVIEW', 'ON_HOLD'],
    ]);
    expect(
      (await h.commissionsAdmin.list(super_, { status: 'FROZEN' })).items,
    ).toHaveLength(1);
    expect(
      (await h.commissionsAdmin.list(super_, { agentId: 'nobody' })).items,
    ).toHaveLength(0);
    const first = await h.commissionsAdmin.list(super_, { limit: 1 });
    expect(first.nextCursor).not.toBeNull();
  });
});

describe('approve', () => {
  it.each(['READY', 'IN_REVIEW'] as const)(
    'approves a %s commission and credits the ledger once',
    async (from) => {
      const c = await make(1, from);
      h.clock.set(LATE);
      const view = await h.commissionsAdmin.approve(super_, c.id, REASON);
      expect(view).toMatchObject({ status: 'APPROVED', creditedPaise: 950 });
      expect(await h.ledger.balance('agent-1')).toBe(950);
      expect(h.audit.entries.at(-1)).toMatchObject({
        actorId: SUPER,
        action: 'commission.approve',
        reason: REASON,
      });
    },
  );

  it.each([
    'ON_HOLD',
    'AWAITING_VERIFICATION',
    'FROZEN',
    'APPROVED',
    'PAID',
    'CANCELLED',
    'REVERSED',
  ] as const)('refuses a %s commission', async (from) => {
    const c = await make(1, from);
    await expect(
      h.commissionsAdmin.approve(super_, c.id, REASON),
    ).rejects.toMatchObject({ code: 'COMMISSION_STATUS_NOT_ALLOWED' });
    expect(await h.ledger.balance('agent-1')).toBe(0);
  });

  it('refuses while the agent is not active, and while the amount is unknown', async () => {
    const c = await make(1, 'READY');
    await h.agents.update('agent-1', { status: 'SUSPENDED' });
    await expect(
      h.commissionsAdmin.approve(super_, c.id, REASON),
    ).rejects.toMatchObject({
      code: 'AGENT_STATUS_NOT_ALLOWED',
      agentStatus: 'SUSPENDED',
    });
    await h.agents.update('agent-1', { status: 'ACTIVE' });
    await h.commissions.update(c.id, { amountPaise: null, basePaise: null });
    await expect(
      h.commissionsAdmin.approve(super_, c.id, REASON),
    ).rejects.toMatchObject({
      code: 'COMMISSION_AMOUNT_NOT_SET',
    });
  });

  it('unknown commission, missing reason, and a failed audit leaves nothing behind', async () => {
    await expect(
      h.commissionsAdmin.approve(super_, 'nope', REASON),
    ).rejects.toMatchObject({
      code: 'COMMISSION_NOT_FOUND',
    });
    const c = await make(1, 'READY');
    await expect(
      h.commissionsAdmin.approve(super_, c.id, 'no'),
    ).rejects.toMatchObject({
      fields: ['reason'],
    });
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(
      h.commissionsAdmin.approve(super_, c.id, REASON),
    ).rejects.toThrow('audit down');
    expect((await h.commissions.findById(c.id))?.status).toBe('READY');
    expect(await h.ledger.balance('agent-1')).toBe(0);
  });
});

describe('cancel', () => {
  it.each([
    'ON_HOLD',
    'AWAITING_VERIFICATION',
    'IN_REVIEW',
    'FROZEN',
    'READY',
  ] as const)(
    'cancels a %s commission without touching the ledger',
    async (from) => {
      const c = await make(1, from);
      const view = await h.commissionsAdmin.cancel(super_, c.id, REASON);
      expect(view.status).toBe('CANCELLED');
      expect(view.publicStatus).toBe('CANCELLED');
      expect(h.ledger.all).toHaveLength(0);
    },
  );

  it('cancels an approved commission and takes back the credit with one adjustment', async () => {
    const c = await make(1, 'READY');
    await h.commissionsAdmin.approve(super_, c.id, REASON);
    const view = await h.commissionsAdmin.cancel(super_, c.id, 'paid in error');
    expect(view).toMatchObject({ status: 'CANCELLED', reversedPaise: 950 });
    expect(await h.ledger.balance('agent-1')).toBe(0);
    expect(
      (await h.ledger.findByKey(`commission-cancel:${c.id}`))?.reason,
    ).toBe('paid in error');
  });

  it('only takes back what a refund has not already reversed', async () => {
    const c = await make(1, 'READY');
    await h.commissionsAdmin.approve(super_, c.id, REASON);
    await h.events.onPaymentRefunded(
      h.paymentRefunded(1, 1, {
        refundedPaise: 2_802,
        totalRefundedPaise: 2_802,
        fullyRefunded: false,
      }),
    );
    expect(await h.ledger.balance('agent-1')).toBe(950 - 237);
    await h.commissionsAdmin.cancel(super_, c.id, REASON);
    expect(await h.ledger.balance('agent-1')).toBe(0);
  });

  it('refuses a commission in a payout, and PAID, CANCELLED or REVERSED ones', async () => {
    const c = await make(1, 'APPROVED');
    await h.commissions.update(c.id, { creditedPaise: 950 });
    await h.payouts.create({
      id: 'po-1',
      agentId: 'agent-1',
      period: '2026-11',
      amountPaise: 950,
      taxWithheldPaise: 0,
      netPaise: 950,
      status: 'CREATED',
      reference: null,
      paidAt: null,
      cancelReason: null,
      cancelledAt: null,
      createdBy: SUPER,
      createdAt: T0,
    });
    await h.commissions.attachToPayout([c.id], 'po-1');
    await expect(
      h.commissionsAdmin.cancel(super_, c.id, REASON),
    ).rejects.toMatchObject({
      code: 'COMMISSION_IN_PAYOUT',
    });
    for (const [n, st] of [
      [2, 'PAID'],
      [3, 'CANCELLED'],
      [4, 'REVERSED'],
    ] as const) {
      const other = await make(n, st);
      await expect(
        h.commissionsAdmin.cancel(super_, other.id, REASON),
      ).rejects.toMatchObject({ code: 'COMMISSION_STATUS_NOT_ALLOWED' });
    }
  });

  it('the audit row is written in the same transaction: a failed adjustment removes it', async () => {
    const c = await make(1, 'READY');
    await h.commissionsAdmin.approve(super_, c.id, REASON);
    const before = h.audit.entries.length;
    jest
      .spyOn(h.ledger, 'append')
      .mockRejectedValueOnce(new Error('ledger down'));
    await expect(
      h.commissionsAdmin.cancel(super_, c.id, REASON),
    ).rejects.toThrow('ledger down');
    expect(h.audit.entries).toHaveLength(before);
    expect((await h.commissions.findById(c.id))?.status).toBe('APPROVED');
  });

  it('losing a race throws and changes nothing', async () => {
    const c = await make(1, 'READY');
    jest.spyOn(h.commissions, 'transition').mockResolvedValueOnce(null);
    await expect(
      h.commissionsAdmin.cancel(super_, c.id, REASON),
    ).rejects.toMatchObject({
      code: 'CONCURRENT_CHANGE',
    });
  });
});

describe('override', () => {
  it('sets the amount of an open commission; the status does not change', async () => {
    const c = await make(1, 'IN_REVIEW');
    const view = await h.commissionsAdmin.override(super_, c.id, 500, REASON);
    expect(view).toMatchObject({ amountPaise: 500, status: 'IN_REVIEW' });
    expect(h.audit.entries.at(-1)).toMatchObject({
      action: 'commission.override',
      before: { amountPaise: 950 },
      after: { amountPaise: 500 },
    });
    expect(h.ledger.all).toHaveLength(0);
  });

  it('can set a missing amount (base not decided) and a zero amount', async () => {
    const c = await make(1, 'ON_HOLD');
    await h.commissions.update(c.id, { amountPaise: null, basePaise: null });
    expect(
      (await h.commissionsAdmin.override(super_, c.id, 0, REASON)).amountPaise,
    ).toBe(0);
  });

  it('corrects the credit of an approved commission with one adjustment for the difference', async () => {
    const c = await make(1, 'READY');
    await h.commissionsAdmin.approve(super_, c.id, REASON);
    const view = await h.commissionsAdmin.override(super_, c.id, 1000, REASON);
    expect(view).toMatchObject({ amountPaise: 1000, creditedPaise: 1000 });
    expect(await h.ledger.balance('agent-1')).toBe(1000);
    await h.commissionsAdmin.override(super_, c.id, 300, REASON);
    expect(await h.ledger.balance('agent-1')).toBe(300);
  });

  it('refuses above what the member paid, a bad amount, and a closed or attached commission', async () => {
    const c = await make(1, 'READY');
    await expect(
      h.commissionsAdmin.override(super_, c.id, 11_211, REASON),
    ).rejects.toMatchObject({ code: 'AMOUNT_EXCEEDS_PAID' });
    expect(
      (await h.commissionsAdmin.override(super_, c.id, 11_210, REASON))
        .amountPaise,
    ).toBe(11_210);
    for (const bad of [-1, 1.5, Number.NaN]) {
      await expect(
        h.commissionsAdmin.override(super_, c.id, bad, REASON),
      ).rejects.toMatchObject({ fields: ['amountPaise'] });
    }
    const paid = await make(2, 'PAID');
    await expect(
      h.commissionsAdmin.override(super_, paid.id, 1, REASON),
    ).rejects.toMatchObject({ code: 'COMMISSION_STATUS_NOT_ALLOWED' });
  });

  it('refuses a typed amount over a commission a partial refund already reduced', async () => {
    const c = await make(1, 'IN_REVIEW');
    await h.events.onPaymentRefunded(
      h.paymentRefunded(1, 1, {
        refundedPaise: 2_802,
        totalRefundedPaise: 2_802,
        fullyRefunded: false,
      }),
    );
    expect((await h.commissions.findById(c.id))?.amountPaise).toBe(712);
    await expect(
      h.commissionsAdmin.override(super_, c.id, 800, REASON),
    ).rejects.toMatchObject({ code: 'COMMISSION_PARTLY_REFUNDED' });
    expect((await h.commissions.findById(c.id))?.amountPaise).toBe(712);
  });

  it('will not drop an approved amount below what refunds already reversed', async () => {
    const c = await make(1, 'READY');
    await h.commissionsAdmin.approve(super_, c.id, REASON);
    await h.events.onPaymentRefunded(
      h.paymentRefunded(1, 1, {
        refundedPaise: 2_802,
        totalRefundedPaise: 2_802,
        fullyRefunded: false,
      }),
    );
    await expect(
      h.commissionsAdmin.override(super_, c.id, 100, REASON),
    ).rejects.toMatchObject({ fields: ['amountPaise'] });
  });

  it('a failed adjustment removes the audit row and the new amount', async () => {
    const c = await make(1, 'READY');
    await h.commissionsAdmin.approve(super_, c.id, REASON);
    const before = h.audit.entries.length;
    jest
      .spyOn(h.ledger, 'append')
      .mockRejectedValueOnce(new Error('ledger down'));
    await expect(
      h.commissionsAdmin.override(super_, c.id, 1000, REASON),
    ).rejects.toThrow('ledger down');
    expect(h.audit.entries).toHaveLength(before);
    expect((await h.commissions.findById(c.id))?.amountPaise).toBe(950);
  });
});
