import {
  buildCreditEntry,
  buildPayoutDebitEntry,
  buildReversalEntry,
} from '../commission/ledger-entries';
import type {
  AgentPayoutRecord,
  CommissionRecord,
  CommissionStatusValue,
} from '../ports/agent-commission-ports';
import { PAYOUT_MINIMUM_AMOUNT_PAISE_KEY } from '../settings/agent-program-settings';
import {
  type AgentHarness,
  expectServiceError,
  makeAgentHarness,
  START,
} from '../testing/agent-test-harness';
import {
  MAX_MONEY_PAGE_LIMIT,
  UNKNOWN_PLAN_NAME,
  UNKNOWN_REFERRAL_DISPLAY_NAME,
} from './agent-money.service';

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const FCM = 'f'.repeat(40);

let h: AgentHarness;

beforeEach(() => {
  h = makeAgentHarness({ [PAYOUT_MINIMUM_AMOUNT_PAISE_KEY]: 50_000 });
});

const asAgent = async (status = 'ACTIVE', id = 'agent-1') => {
  await h.seedAgent(status, { id });
  return h.claimsOf(await h.signInAs());
};

/** Commission `n`, created `n` hours after START (higher n = newer). */
const commission = (
  n: number,
  o: Partial<CommissionRecord> = {},
): Promise<CommissionRecord> =>
  h.commissions.create({
    id: `c-${n}`,
    agentId: 'agent-1',
    attributionId: `attr-${n}`,
    paymentId: `pay-${n}`,
    phoneHash: `v1:member-${n}`,
    policyVersionId: 'pol-1',
    status: 'ON_HOLD',
    calcType: 'PERCENTAGE',
    ruleValue: 1000,
    basePaise: 99_900,
    amountPaise: 9_990,
    amountPaidPaise: 99_900,
    taxableAmountPaise: 99_900,
    creditedPaise: 0,
    reversedPaise: 0,
    holdUntil: new Date(START.getTime() + n * HOUR + 14 * DAY),
    reviewReasons: [],
    approvedAt: null,
    paidAt: null,
    cancelledAt: null,
    payoutId: null,
    createdAt: new Date(START.getTime() + n * HOUR),
    ...o,
  });

const payout = (
  n: number,
  o: Partial<AgentPayoutRecord> = {},
): Promise<AgentPayoutRecord> =>
  h.payouts.create({
    id: `p-${n}`,
    agentId: 'agent-1',
    period: `2026-${String(n).padStart(2, '0')}`,
    amountPaise: 60_000,
    taxWithheldPaise: 0,
    netPaise: 60_000,
    status: 'CREATED',
    reference: null,
    paidAt: null,
    cancelReason: null,
    cancelledAt: null,
    createdBy: 'staff-1',
    createdAt: new Date(START.getTime() + n * DAY),
    ...o,
  });

const credit = (
  commissionId: string,
  amountPaise: number,
  agentId = 'agent-1',
) =>
  h.ledger.append(
    buildCreditEntry({
      agentId,
      commissionId,
      amountPaise,
      calcType: 'PERCENTAGE',
      value: 1000,
      ruleSnapshot: {},
    }),
  );

describe('GET /agent/commissions (listCommissions)', () => {
  it('maps a commission to the contract shape, with dates in Indian time', async () => {
    const claims = await asAgent();
    await commission(1, {
      status: 'APPROVED',
      // 20:00 UTC is the next calendar day in India.
      createdAt: new Date('2026-10-28T20:00:00.000Z'),
      holdUntil: new Date('2026-11-11T20:00:00.000Z'),
      approvedAt: new Date('2026-11-11T21:00:00.000Z'),
    });
    h.commissionDisplay.shown.set('c-1', {
      referralDisplayName: 'Priya S.',
      planName: 'Gold',
    });
    expect(await h.money.listCommissions(claims)).toEqual({
      items: [
        {
          id: 'c-1',
          referralId: 'attr-1',
          referralDisplayName: 'Priya S.',
          planName: 'Gold',
          basePaise: 99_900,
          amountPaise: 9_990,
          rate: { calcType: 'PERCENTAGE', value: 1000 },
          status: 'APPROVED',
          earnedOn: '2026-10-29',
          holdEndsOn: '2026-11-12',
          approvedOn: '2026-11-12',
          paidOn: null,
        },
      ],
      nextCursor: null,
    });
  });

  it.each<[CommissionStatusValue, string]>([
    ['ON_HOLD', 'ON_HOLD'],
    ['AWAITING_VERIFICATION', 'ON_HOLD'],
    ['IN_REVIEW', 'ON_HOLD'],
    ['FROZEN', 'ON_HOLD'],
    ['READY', 'ON_HOLD'],
    ['APPROVED', 'APPROVED'],
    ['PAID', 'PAID'],
    ['CANCELLED', 'CANCELLED'],
    ['REVERSED', 'CANCELLED'],
  ])('shows the internal %s as %s only', async (internal, shown) => {
    const claims = await asAgent();
    await commission(1, { status: internal });
    const [item] = (await h.money.listCommissions(claims)).items;
    expect(item.status).toBe(shown);
    expect(JSON.stringify(item)).not.toMatch(
      /IN_REVIEW|FROZEN|READY|AWAITING|REVERSED|reviewReasons|phoneHash|paymentId/,
    );
  });

  it('a cancelled commission has no hold end date', async () => {
    const claims = await asAgent();
    await commission(1, { status: 'REVERSED' });
    expect(
      (await h.money.listCommissions(claims)).items[0].holdEndsOn,
    ).toBeNull();
  });

  it('an amount not yet known is shown as 0', async () => {
    const claims = await asAgent();
    await commission(1, { basePaise: null, amountPaise: null });
    expect((await h.money.listCommissions(claims)).items[0]).toMatchObject({
      basePaise: 0,
      amountPaise: 0,
    });
  });

  it('a member or plan that can no longer be read gets the neutral names', async () => {
    const claims = await asAgent();
    await commission(1);
    expect((await h.money.listCommissions(claims)).items[0]).toMatchObject({
      referralDisplayName: UNKNOWN_REFERRAL_DISPLAY_NAME,
      planName: UNKNOWN_PLAN_NAME,
    });
  });

  it('shows only the caller own commissions', async () => {
    const claims = await asAgent();
    await commission(1);
    await commission(2, { agentId: 'agent-2' });
    const page = await h.money.listCommissions(claims);
    expect(page.items.map((c) => c.id)).toEqual(['c-1']);
  });

  it('pages newest first with an opaque cursor, and the last page has none', async () => {
    const claims = await asAgent();
    for (const n of [1, 2, 3, 4, 5]) await commission(n);
    const first = await h.money.listCommissions(claims, { limit: 2 });
    expect(first.items.map((c) => c.id)).toEqual(['c-5', 'c-4']);
    const second = await h.money.listCommissions(claims, {
      limit: 2,
      cursor: first.nextCursor!,
    });
    expect(second.items.map((c) => c.id)).toEqual(['c-3', 'c-2']);
    const last = await h.money.listCommissions(claims, {
      limit: 2,
      cursor: second.nextCursor!,
    });
    expect(last).toMatchObject({ nextCursor: null });
    expect(last.items.map((c) => c.id)).toEqual(['c-1']);
  });

  it('a page exactly full has no next cursor', async () => {
    const claims = await asAgent();
    for (const n of [1, 2]) await commission(n);
    expect(
      (await h.money.listCommissions(claims, { limit: 2 })).nextCursor,
    ).toBeNull();
  });

  it('filters by the PUBLIC status, across pages', async () => {
    const claims = await asAgent();
    await commission(1, { status: 'IN_REVIEW' });
    await commission(2, { status: 'APPROVED' });
    await commission(3, { status: 'FROZEN' });
    await commission(4, { status: 'PAID' });
    await commission(5, { status: 'ON_HOLD' });
    const first = await h.money.listCommissions(claims, {
      status: 'ON_HOLD',
      limit: 2,
    });
    expect(first.items.map((c) => c.id)).toEqual(['c-5', 'c-3']);
    const second = await h.money.listCommissions(claims, {
      status: 'ON_HOLD',
      limit: 2,
      cursor: first.nextCursor!,
    });
    expect(second).toMatchObject({ nextCursor: null });
    expect(second.items.map((c) => c.id)).toEqual(['c-1']);
    const cancelled = await h.money.listCommissions(claims, {
      status: 'CANCELLED',
    });
    expect(cancelled.items).toEqual([]);
  });

  it.each([
    [{ limit: 0 }, ['limit']],
    [{ limit: MAX_MONEY_PAGE_LIMIT + 1 }, ['limit']],
    [{ limit: 1.5 }, ['limit']],
    [{ cursor: 'not-a-cursor' }, ['cursor']],
    [{ status: 'IN_REVIEW' }, ['status']],
    [{ status: 'REVERSED' }, ['status']],
  ])('refuses %p', async (query, fields) => {
    const claims = await asAgent();
    await expectServiceError(
      h.money.listCommissions(claims, query),
      'VALIDATION_FAILED',
      { fields },
    );
  });

  it('accepts the maximum page size', async () => {
    const claims = await asAgent();
    await expect(
      h.money.listCommissions(claims, { limit: MAX_MONEY_PAGE_LIMIT }),
    ).resolves.toMatchObject({ items: [] });
  });

  it.each(['SUSPENDED', 'TERMINATED'])(
    'a %s agent can still read it',
    async (status) => {
      const claims = await asAgent(status);
      await commission(1);
      expect((await h.money.listCommissions(claims)).items).toHaveLength(1);
    },
  );

  it.each(['PENDING_APPROVAL', 'REJECTED'])(
    'a %s agent is refused',
    async (status) => {
      const claims = await asAgent(status);
      await expectServiceError(
        h.money.listCommissions(claims),
        'AGENT_NOT_ACTIVE',
        {
          agentStatus: status,
        },
      );
    },
  );
});

describe('GET /agent/balance (getBalance)', () => {
  it('a new agent has nothing', async () => {
    const claims = await asAgent();
    expect(await h.money.getBalance(claims)).toEqual({
      onHoldPaise: 0,
      availablePaise: 0,
      paidPaise: 0,
      minPayoutPaise: 50_000,
      canRequestPayout: false,
    });
  });

  it('totals the public ON_HOLD commissions, the ledger and the paid payouts', async () => {
    const claims = await asAgent();
    await commission(1, { status: 'ON_HOLD', amountPaise: 1_000 });
    await commission(2, { status: 'IN_REVIEW', amountPaise: 2_000 });
    await commission(3, { status: 'FROZEN', amountPaise: 4_000 });
    await commission(4, { status: 'READY', amountPaise: null });
    await commission(5, { status: 'APPROVED', amountPaise: 8_000 });
    await commission(6, { status: 'CANCELLED', amountPaise: 16_000 });
    await commission(7, {
      status: 'ON_HOLD',
      amountPaise: 32_000,
      agentId: 'agent-2',
    });
    await credit('c-5', 8_000);
    await credit('c-x', 70_000);
    await credit('c-y', 99_000, 'agent-2');
    await payout(1, { status: 'PAID', amountPaise: 60_000, reference: 'UTR1' });
    await payout(2, { status: 'PAID', amountPaise: 30_000, reference: 'UTR2' });
    await payout(3, { status: 'CREATED', amountPaise: 5_000 });
    await payout(4, { status: 'CANCELLED', amountPaise: 7_000 });
    await payout(5, { status: 'PAID', amountPaise: 1, agentId: 'agent-2' });
    expect(await h.money.getBalance(claims)).toEqual({
      onHoldPaise: 7_000,
      availablePaise: 78_000,
      paidPaise: 90_000,
      minPayoutPaise: 50_000,
      canRequestPayout: true,
    });
  });

  it('available is the ledger after payouts are set aside and refunds clawed back', async () => {
    const claims = await asAgent();
    await credit('c-1', 60_000);
    await h.ledger.append(
      buildPayoutDebitEntry({
        agentId: 'agent-1',
        payoutId: 'p-1',
        amountPaise: 20_000,
      }),
    );
    await h.ledger.append(
      buildReversalEntry({
        agentId: 'agent-1',
        commissionId: 'c-1',
        refundId: 'r-1',
        reversalPaise: 5_000,
      }),
    );
    expect(await h.money.getBalance(claims)).toMatchObject({
      availablePaise: 35_000,
      canRequestPayout: false,
    });
  });

  it('can request a payout exactly at the minimum, not one paisa below', async () => {
    const claims = await asAgent();
    await credit('c-1', 49_999);
    expect((await h.money.getBalance(claims)).canRequestPayout).toBe(false);
    await credit('c-2', 1);
    expect(await h.money.getBalance(claims)).toMatchObject({
      availablePaise: 50_000,
      canRequestPayout: true,
    });
  });

  it('uses the minimum payout setting, not a constant', async () => {
    const claims = await asAgent();
    h.settings.set(PAYOUT_MINIMUM_AMOUNT_PAISE_KEY, 10_000);
    await credit('c-1', 10_000);
    expect(await h.money.getBalance(claims)).toMatchObject({
      minPayoutPaise: 10_000,
      canRequestPayout: true,
    });
  });

  it('a negative ledger (a refund after a payout) is shown as 0 available', async () => {
    const claims = await asAgent();
    await h.ledger.append(
      buildReversalEntry({
        agentId: 'agent-1',
        commissionId: 'c-1',
        refundId: 'r-1',
        reversalPaise: 5_000,
      }),
    );
    expect(await h.money.getBalance(claims)).toMatchObject({
      availablePaise: 0,
      canRequestPayout: false,
    });
  });

  it('counts every commission and payout, past one read batch', async () => {
    const claims = await asAgent();
    for (let n = 1; n <= 450; n++) await commission(n, { amountPaise: 1 });
    for (let n = 1; n <= 450; n++) {
      await payout(n, { status: 'PAID', amountPaise: 2, period: `p-${n}` });
    }
    expect(await h.money.getBalance(claims)).toMatchObject({
      onHoldPaise: 450,
      paidPaise: 900,
    });
  });

  it('answers 503 while the minimum payout is not set', async () => {
    const claims = await asAgent();
    h.settings.remove(PAYOUT_MINIMUM_AMOUNT_PAISE_KEY);
    await expect(h.money.getBalance(claims)).rejects.toMatchObject({
      name: 'AgentConfigError',
    });
  });

  it.each(['PENDING_APPROVAL', 'REJECTED'])(
    'a %s agent is refused',
    async (status) => {
      const claims = await asAgent(status);
      await expectServiceError(h.money.getBalance(claims), 'AGENT_NOT_ACTIVE');
    },
  );

  it('a TERMINATED agent can still read it', async () => {
    const claims = await asAgent('TERMINATED');
    await expect(h.money.getBalance(claims)).resolves.toMatchObject({
      paidPaise: 0,
    });
  });
});

describe('GET /agent/payouts (listPayouts)', () => {
  it('maps a payout, with the commission count and the reference only once paid', async () => {
    const claims = await asAgent();
    await payout(1, {
      status: 'PAID',
      reference: 'UTR123',
      paidAt: new Date('2026-11-01T19:00:00.000Z'),
    });
    await payout(2, { status: 'CANCELLED', reference: 'should-not-show' });
    await commission(1, { status: 'PAID', payoutId: 'p-1' });
    await commission(2, { status: 'PAID', payoutId: 'p-1' });
    const page = await h.money.listPayouts(claims);
    expect(page).toEqual({
      items: [
        {
          id: 'p-2',
          amountPaise: 60_000,
          status: 'CANCELLED',
          reference: null,
          createdOn: '2026-10-30',
          paidOn: null,
          commissionCount: 0,
        },
        {
          id: 'p-1',
          amountPaise: 60_000,
          status: 'PAID',
          reference: 'UTR123',
          createdOn: '2026-10-29',
          paidOn: '2026-11-02',
          commissionCount: 2,
        },
      ],
      nextCursor: null,
    });
  });

  it('shows only the caller own payouts, a page at a time', async () => {
    const claims = await asAgent();
    for (const n of [1, 2, 3]) await payout(n);
    await payout(4, { agentId: 'agent-2' });
    const first = await h.money.listPayouts(claims, { limit: 2 });
    expect(first.items.map((p) => p.id)).toEqual(['p-3', 'p-2']);
    const second = await h.money.listPayouts(claims, {
      limit: 2,
      cursor: first.nextCursor!,
    });
    expect(second).toMatchObject({ nextCursor: null });
    expect(second.items.map((p) => p.id)).toEqual(['p-1']);
  });

  it.each([
    [{ limit: 0 }, ['limit']],
    [{ limit: 51 }, ['limit']],
    [{ cursor: '' }, ['cursor']],
  ])('refuses %p', async (query, fields) => {
    const claims = await asAgent();
    await expectServiceError(
      h.money.listPayouts(claims, query),
      'VALIDATION_FAILED',
      {
        fields,
      },
    );
  });

  it('a TERMINATED agent can still read it; a PENDING one cannot', async () => {
    const terminated = await asAgent('TERMINATED');
    await expect(h.money.listPayouts(terminated)).resolves.toMatchObject({
      items: [],
    });
    h = makeAgentHarness({ [PAYOUT_MINIMUM_AMOUNT_PAISE_KEY]: 50_000 });
    const pending = await asAgent('PENDING_APPROVAL');
    await expectServiceError(h.money.listPayouts(pending), 'AGENT_NOT_ACTIVE');
  });
});

describe('POST /agent/devices (registerDevice)', () => {
  it('stores the device for the caller', async () => {
    const claims = await asAgent();
    await h.money.registerDevice(claims, {
      fcmToken: FCM,
      platform: 'ANDROID',
    });
    expect(h.devices.byToken.get(FCM)).toEqual({
      agentId: 'agent-1',
      fcmToken: FCM,
      platform: 'ANDROID',
      isActive: true,
    });
  });

  it('is idempotent, and a token held by another agent moves to the caller', async () => {
    await h.devices.register({
      agentId: 'agent-9',
      fcmToken: FCM,
      platform: 'IOS',
    });
    const claims = await asAgent();
    await h.money.registerDevice(claims, { fcmToken: FCM, platform: 'IOS' });
    await h.money.registerDevice(claims, { fcmToken: FCM, platform: 'IOS' });
    expect([...h.devices.byToken.values()]).toEqual([
      { agentId: 'agent-1', fcmToken: FCM, platform: 'IOS', isActive: true },
    ]);
  });

  it.each([
    [{ fcmToken: FCM, platform: 'WEB' }, ['platform']],
    [{ fcmToken: FCM, platform: 'android' }, ['platform']],
    [{ fcmToken: FCM }, ['platform']],
    [{ fcmToken: 'x'.repeat(19), platform: 'IOS' }, ['fcmToken']],
    [{ fcmToken: 'x'.repeat(4097), platform: 'IOS' }, ['fcmToken']],
    [{ fcmToken: 42, platform: 'IOS' }, ['fcmToken']],
    [{}, ['fcmToken', 'platform']],
  ])('refuses %p and stores nothing', async (body, fields) => {
    const claims = await asAgent();
    await expectServiceError(
      h.money.registerDevice(claims, body),
      'VALIDATION_FAILED',
      {
        fields,
      },
    );
    expect(h.devices.byToken.size).toBe(0);
  });

  it('accepts the shortest and the longest token', async () => {
    const claims = await asAgent();
    await h.money.registerDevice(claims, {
      fcmToken: 'x'.repeat(20),
      platform: 'IOS',
    });
    await h.money.registerDevice(claims, {
      fcmToken: 'y'.repeat(4096),
      platform: 'ANDROID',
    });
    expect(h.devices.byToken.size).toBe(2);
  });

  it.each(['PENDING_APPROVAL', 'REJECTED', 'ACTIVE', 'SUSPENDED'])(
    'a %s agent may register (the approval push needs it)',
    async (status) => {
      const claims = await asAgent(status);
      await h.money.registerDevice(claims, {
        fcmToken: FCM,
        platform: 'ANDROID',
      });
      expect(h.devices.byToken.size).toBe(1);
    },
  );

  it('a TERMINATED agent may not', async () => {
    const claims = await asAgent('TERMINATED');
    await expectServiceError(
      h.money.registerDevice(claims, { fcmToken: FCM, platform: 'ANDROID' }),
      'AGENT_NOT_ACTIVE',
    );
    expect(h.devices.byToken.size).toBe(0);
  });
});
