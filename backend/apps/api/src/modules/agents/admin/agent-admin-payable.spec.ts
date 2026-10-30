import { buildReversalEntry } from '../commission/ledger-entries';
import { AgentConfigError } from '../config/agent-config.service';
import { AgentMoneyError } from '../errors/agent-money-error';
import { AgentPermissionDeniedError } from '../ports/agent-platform-ports';
import {
  PARTNER,
  PAYER,
  actorOf,
  makeAdminHarness,
  type AdminHarness,
} from '../testing/agent-admin-harness';
import { DAY, HOUR, T0 } from '../testing/agent-commission-harness';

let h: AdminHarness;
const payer = actorOf(PAYER);
const HOLD_END = new Date(T0.getTime() + HOUR + 14 * DAY);
const PAYOUT_DAY = new Date(HOLD_END.getTime() + 10 * DAY);
const PERIOD = '2026-11';

async function approvedCommission(n: number, agentId: string, amount: number) {
  await h.seedAttribution(n, { agentId });
  const c = await h.commissions.create({
    id: `com-${n}`,
    agentId,
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
  await h.uow.run((tx) => h.approval.approve(c, HOLD_END, null, 'seed', tx));
}

/** agent-1: ready to pay. agent-2: no PAN, no verified details, below minimum. */
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
  await h.seedAgent('ACTIVE', {
    id: 'agent-2',
    name: 'Priya Sharma',
    phoneE164: '+919000000001',
  });
  await approvedCommission(1, 'agent-1', 60_000);
  await approvedCommission(7, 'agent-2', 100);
  h.clock.set(PAYOUT_DAY);
});

const payable = (
  q: { eligible?: boolean; cursor?: string; limit?: number } = {},
) => h.payoutsAdmin.listPayable(payer, { period: PERIOD, ...q });

describe('GET /admin/payouts/payable (service)', () => {
  it('lists every agent with approved, unpaid commission, with every reason', async () => {
    const { items, nextCursor } = await payable();
    expect(nextCursor).toBeNull();
    expect(items.map((i) => [i.agentId, i.eligible, i.reasons])).toEqual([
      ['agent-1', true, []],
      [
        'agent-2',
        false,
        ['PAN_NOT_VERIFIED', 'DETAILS_NOT_VERIFIED', 'BELOW_MINIMUM'],
      ],
    ]);
    expect(items[0]).toMatchObject({
      agentName: 'Ravi Kumar',
      agentCode: 'NM7K2P9X',
      agentStatus: 'ACTIVE',
      period: PERIOD,
      balancePaise: 60_000,
      commissionCount: 1,
      panVerified: true,
      payoutDetails: { method: 'UPI', display: 'r***@okbank' },
      warnings: ['TAX_RULE_NOT_SET'],
    });
    expect(items[1]).toMatchObject({
      agentCode: null,
      payoutDetails: null,
      panVerified: false,
    });
  });

  it('agrees with create: eligible creates, ineligible refuses with the same reasons', async () => {
    const [ready, notReady] = (await payable()).items;
    await expect(
      h.payoutsAdmin.create(payer, {
        agentId: ready.agentId,
        period: PERIOD,
        reason: 'monthly payout',
      }),
    ).resolves.toMatchObject({ created: true });
    const refusal = await h.payoutsAdmin
      .create(payer, {
        agentId: notReady.agentId,
        period: PERIOD,
        reason: 'monthly payout',
      })
      .catch((e: unknown) => e);
    expect(refusal).toBeInstanceOf(AgentMoneyError);
    expect((refusal as AgentMoneyError).reasons).toEqual(notReady.reasons);
  });

  it('a payout already created for the period: PAYOUT_EXISTS (only unattached commission counts)', async () => {
    await approvedCommission(2, 'agent-1', 60_000);
    await h.payoutsAdmin.create(payer, {
      agentId: 'agent-1',
      period: PERIOD,
      reason: 'monthly payout',
    });
    await approvedCommission(3, 'agent-1', 60_000);
    const one = (await payable()).items.find((i) => i.agentId === 'agent-1');
    expect(one?.reasons).toEqual(['PAYOUT_EXISTS']);
    expect(one?.balancePaise).toBe(60_000);
  });

  it('eligible filters; pages by agent with an opaque cursor', async () => {
    expect(
      (await payable({ eligible: true })).items.map((i) => i.agentId),
    ).toEqual(['agent-1']);
    expect(
      (await payable({ eligible: false })).items.map((i) => i.agentId),
    ).toEqual(['agent-2']);
    const first = await payable({ limit: 1 });
    expect(first.items.map((i) => i.agentId)).toEqual(['agent-1']);
    expect(first.nextCursor).not.toContain('agent-1');
    const second = await payable({
      limit: 1,
      cursor: first.nextCursor as string,
    });
    expect(second.items.map((i) => i.agentId)).toEqual(['agent-2']);
    expect(second.nextCursor).toBeNull();
  });

  it('a set tax rule is TAX_RULE_UNSUPPORTED (pending the CA); no warning then', async () => {
    h.settings.set('payout.tax_withholding', { rate: 10 });
    const one = (await payable()).items[0];
    expect(one.reasons).toEqual(['TAX_RULE_UNSUPPORTED']);
    expect(one.warnings).toEqual([]);
  });

  it('a missing setting is AgentConfigError (503 SETTINGS_NOT_CONFIGURED)', async () => {
    h.settings.remove('payout.minimum_amount_paise');
    await expect(payable()).rejects.toBeInstanceOf(AgentConfigError);
  });

  it('a missing payout-details wait is refused too, naming the key', async () => {
    h.settings.remove('agent.payout_details_wait_hours');
    const error = await payable().catch((e: unknown) => e);
    expect(error).toBeInstanceOf(AgentConfigError);
    expect((error as AgentConfigError).missing).toEqual([
      'agent.payout_details_wait_hours',
    ]);
  });

  it('shows the PRIMARY code, not the first one', async () => {
    await h.seedAgent('ACTIVE', {
      id: 'agent-3',
      name: 'Mala',
      phoneE164: '+919000000002',
    });
    await h.codes.create({
      id: 'code-3a',
      agentId: 'agent-3',
      code: 'NM3H4J5K',
      isPrimary: false,
      isActive: true,
      createdAt: T0,
    });
    await h.codes.create({
      id: 'code-3b',
      agentId: 'agent-3',
      code: 'NM7K2P9Y',
      isPrimary: true,
      isActive: true,
      createdAt: T0,
    });
    await approvedCommission(9, 'agent-3', 100);
    const three = (await payable()).items.find((i) => i.agentId === 'agent-3');
    expect(three?.agentCode).toBe('NM7K2P9Y');
  });

  it('the balance is credited minus reversed', async () => {
    await h.commissions.update('com-1', { reversedPaise: 10_000 });
    const one = (await payable()).items.find((i) => i.agentId === 'agent-1');
    expect(one?.balancePaise).toBe(50_000);
  });

  it('a ledger below the commission balance is LEDGER_BALANCE_TOO_LOW', async () => {
    await h.ledger.append(
      buildReversalEntry({
        agentId: 'agent-1',
        commissionId: 'com-1',
        refundId: 'refund-1',
        reversalPaise: 5_000,
      }),
    );
    const one = (await payable()).items.find((i) => i.agentId === 'agent-1');
    expect(one).toMatchObject({
      eligible: false,
      reasons: ['LEDGER_BALANCE_TOO_LOW'],
    });
  });

  it('needs payout.view; a bad period or cursor is VALIDATION_FAILED', async () => {
    await expect(
      h.payoutsAdmin.listPayable(actorOf(PARTNER), { period: PERIOD }),
    ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
    for (const q of [
      { period: '2026-13' },
      { period: PERIOD, cursor: Buffer.from('a b').toString('base64url') },
    ]) {
      const e = await h.payoutsAdmin
        .listPayable(payer, q)
        .catch((x: unknown) => x);
      expect((e as AgentMoneyError).code).toBe('VALIDATION_FAILED');
    }
  });
});
