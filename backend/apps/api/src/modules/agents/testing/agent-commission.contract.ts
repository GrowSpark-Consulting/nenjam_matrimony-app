/**
 * Behaviour suite for the commission policy, commission, ledger and payout
 * repositories, run against BOTH the in-memory fakes (default `pnpm test`)
 * and the Prisma adapters (database-gated, `pnpm test:agent-db`).
 */
import {
  buildAdjustmentEntry,
  buildCreditEntry,
  buildPayoutDebitEntry,
  buildReversalEntry,
} from '../commission/ledger-entries';
import {
  type AgentLedgerRepository,
  type AgentPayoutRecord,
  type AgentPayoutRepository,
  type CommissionPolicyRepository,
  type CommissionPolicyVersionRecord,
  type CommissionRecord,
  type CommissionRepository,
} from '../ports/agent-commission-ports';
import {
  AgentConflictError,
  type AgentRepository,
  type ReferralAttributionRepository,
} from '../ports/agent-data-ports';
import type { AgentUnitOfWork } from '../ports/agent-unit-of-work.port';

export interface AgentCommissionWorld {
  uow: AgentUnitOfWork;
  agents: AgentRepository;
  attributions: ReferralAttributionRepository;
  policy: CommissionPolicyRepository;
  commissions: CommissionRepository;
  ledger: AgentLedgerRepository;
  payouts: AgentPayoutRepository;
  /** Adds a policy version (versions are never written through the port). */
  addPolicyVersion(version: CommissionPolicyVersionRecord): Promise<void>;
  cleanup?(): Promise<void>;
}

const T0 = new Date('2026-10-29T09:00:00.000Z');
const at = (minutes: number) => new Date(T0.getTime() + minutes * 60_000);
const DAY = 86_400_000;

const conflict = (reason: AgentConflictError['reason']): unknown =>
  expect.objectContaining({ name: 'AgentConflictError', reason });

export function defineAgentCommissionContract(
  suiteName: string,
  makeWorld: () => Promise<AgentCommissionWorld>,
): void {
  describe(`${suiteName}: commission, ledger and payout contract`, () => {
    let w: AgentCommissionWorld;

    // Policy versions the suite adds (numbers above 100 never clash with the seeded v1).
    const V101 = {
      id: 'pol-101',
      version: 101,
      calcType: 'PERCENTAGE' as const,
      value: 1000,
      holdDays: 14,
      effectiveFrom: new Date('2020-01-01T00:00:00.000Z'),
    };
    const V102 = {
      ...V101,
      id: 'pol-102',
      version: 102,
      value: 1200,
      holdDays: 7,
      effectiveFrom: new Date('2021-01-01T00:00:00.000Z'),
    };
    const V103 = {
      ...V101,
      id: 'pol-103',
      version: 103,
      value: 1500,
      effectiveFrom: new Date('2099-01-01T00:00:00.000Z'),
    };

    beforeEach(async () => {
      w = await makeWorld();
      for (const n of [1, 2]) {
        await w.agents.create({
          id: `agent-${n}`,
          phoneHash: `v1:hash-${n}`,
          phoneE164: `+91900000000${n}`,
          name: `Agent ${n}`,
          city: 'Madurai',
          state: 'Tamil Nadu',
          panLast4: null,
          panSealed: null,
          createdAt: at(0),
        });
      }
      for (const v of [V101, V102, V103]) await w.addPolicyVersion(v);
      for (let n = 1; n <= 8; n++) {
        await w.attributions.create({
          id: `attr-${n}`,
          memberId: null,
          agentId: n <= 6 ? 'agent-1' : 'agent-2',
          codeId: null,
          source: 'CODE_AT_SIGNUP',
          memberPhoneHash: `v1:member-hash-${n}`,
          attributedAt: at(n),
          status: 'ACTIVE',
          windowEndsAt: at(60 * 24 * 60),
          needsReview: false,
        });
      }
    });
    afterEach(async () => {
      await w.cleanup?.();
    });

    const commission = (
      n: number,
      o: Partial<CommissionRecord> = {},
    ): CommissionRecord => ({
      id: `com-${String(n).padStart(2, '0')}`,
      agentId: n <= 6 ? 'agent-1' : 'agent-2',
      attributionId: `attr-${n}`,
      paymentId: `pay-${n}`,
      phoneHash: `v1:member-hash-${n}`,
      policyVersionId: 'pol-101',
      status: 'ON_HOLD',
      calcType: 'PERCENTAGE',
      ruleValue: 1000,
      basePaise: 8475,
      amountPaise: 848,
      amountPaidPaise: 10000,
      taxableAmountPaise: 8475,
      refundedPaise: 0,
      preRefundAmountPaise: null,
      creditedPaise: 0,
      reversedPaise: 0,
      holdUntil: at(14 * 24 * 60),
      reviewReasons: [],
      approvedAt: null,
      paidAt: null,
      cancelledAt: null,
      payoutId: null,
      createdAt: at(n),
      ...o,
    });

    const payout = (
      n: number,
      o: Partial<AgentPayoutRecord> = {},
    ): AgentPayoutRecord => ({
      id: `po-${String(n).padStart(2, '0')}`,
      agentId: 'agent-1',
      period: '2026-11',
      amountPaise: 60000,
      taxWithheldPaise: 0,
      netPaise: 60000,
      status: 'CREATED',
      reference: null,
      paidAt: null,
      cancelReason: null,
      cancelledAt: null,
      createdBy: 'staff-1',
      createdAt: at(n),
      ...o,
    });

    describe('CommissionPolicyRepository', () => {
      it('finds a version by id', async () => {
        expect(await w.policy.findById('pol-102')).toEqual(V102);
        expect(await w.policy.findById('nope')).toBeNull();
      });

      it('the active version is the newest one already in effect', async () => {
        expect(
          (await w.policy.findActive(new Date('2022-06-01T00:00:00.000Z')))?.id,
        ).toBe('pol-102');
        expect(
          (await w.policy.findActive(new Date('2020-06-01T00:00:00.000Z')))?.id,
        ).toBe('pol-101');
        expect(
          (await w.policy.findActive(new Date('2099-06-01T00:00:00.000Z')))?.id,
        ).toBe('pol-103');
        expect(
          await w.policy.findActive(new Date('2019-01-01T00:00:00.000Z')),
        ).toBeNull();
      });

      it('an agent uses its own policy when assigned, otherwise the active one', async () => {
        const when = new Date('2022-06-01T00:00:00.000Z');
        expect((await w.policy.findForAgent('agent-1', when))?.id).toBe(
          'pol-102',
        );
        await w.policy.assignToAgent('agent-1', 'pol-101');
        expect((await w.policy.findForAgent('agent-1', when))?.id).toBe(
          'pol-101',
        );
        expect((await w.policy.findForAgent('agent-2', when))?.id).toBe(
          'pol-102',
        );
        await w.policy.assignToAgent('agent-1', null);
        expect((await w.policy.findForAgent('agent-1', when))?.id).toBe(
          'pol-102',
        );
      });

      it('refuses to assign an unknown policy', async () => {
        await expect(
          w.policy.assignToAgent('agent-1', 'nope'),
        ).rejects.toThrow();
      });

      it('an assignment made in a transaction is undone with it', async () => {
        await expect(
          w.uow.run(async (tx) => {
            await w.policy.assignToAgent('agent-1', 'pol-101', tx);
            throw new Error('boom');
          }),
        ).rejects.toThrow('boom');
        expect(
          (
            await w.policy.findForAgent(
              'agent-1',
              new Date('2022-06-01T00:00:00.000Z'),
            )
          )?.id,
        ).toBe('pol-102');
      });
    });

    describe('CommissionRepository', () => {
      it('creates and finds by id, payment and attribution', async () => {
        const created = await w.commissions.create(
          commission(1, { reviewReasons: ['SELF_MATCH', 'PAID_BY_AGENT'] }),
        );
        expect(created).toEqual(
          commission(1, { reviewReasons: ['SELF_MATCH', 'PAID_BY_AGENT'] }),
        );
        expect(await w.commissions.findById('com-01')).toEqual(created);
        expect(await w.commissions.findByPaymentId('pay-1')).toEqual(created);
        expect(await w.commissions.findByAttributionId('attr-1')).toEqual(
          created,
        );
        expect(await w.commissions.findById('nope')).toBeNull();
        expect(await w.commissions.findByPaymentId('nope')).toBeNull();
        expect(await w.commissions.findByAttributionId('nope')).toBeNull();
      });

      it('stores a commission with no amount yet', async () => {
        const created = await w.commissions.create(
          commission(1, { basePaise: null, amountPaise: null }),
        );
        expect(created).toMatchObject({ basePaise: null, amountPaise: null });
      });

      it('refuses a second commission for the same payment, attribution or phone hash', async () => {
        await w.commissions.create(commission(1));
        await expect(
          w.commissions.create(
            commission(2, { id: 'com-x1', paymentId: 'pay-1' }),
          ),
        ).rejects.toEqual(conflict('DUPLICATE_COMMISSION'));
        await expect(
          w.commissions.create(
            commission(2, { id: 'com-x2', attributionId: 'attr-1' }),
          ),
        ).rejects.toEqual(conflict('DUPLICATE_COMMISSION'));
        await expect(
          w.commissions.create(
            commission(2, { id: 'com-x3', phoneHash: 'v1:member-hash-1' }),
          ),
        ).rejects.toEqual(conflict('DUPLICATE_COMMISSION'));
        await expect(
          w.commissions.create(commission(2, { id: 'com-01' })),
        ).rejects.toEqual(conflict('DUPLICATE_ID'));
      });

      it('updates only the given fields', async () => {
        await w.commissions.create(
          commission(1, { basePaise: null, amountPaise: null }),
        );
        const updated = await w.commissions.update('com-01', {
          basePaise: 8475,
          amountPaise: 848,
          status: 'APPROVED',
          approvedAt: at(30),
          creditedPaise: 848,
        });
        expect(updated).toMatchObject({
          basePaise: 8475,
          amountPaise: 848,
          status: 'APPROVED',
          approvedAt: at(30),
          creditedPaise: 848,
          reversedPaise: 0,
          agentId: 'agent-1',
        });
        await expect(
          w.commissions.update('nope', { status: 'FROZEN' }),
        ).rejects.toThrow('Unknown commission nope');
      });

      it('stores the refund reduction: running total, reduced amount and the original', async () => {
        await w.commissions.create(commission(1));
        const reduced = await w.commissions.transition('com-01', 'ON_HOLD', {
          refundedPaise: 2802,
          amountPaise: 712,
          preRefundAmountPaise: 848,
        });
        expect(reduced).toMatchObject({
          refundedPaise: 2802,
          amountPaise: 712,
          preRefundAmountPaise: 848,
          status: 'ON_HOLD',
        });
        expect(await w.commissions.findById('com-01')).toMatchObject({
          refundedPaise: 2802,
          preRefundAmountPaise: 848,
        });
        const again = await w.commissions.update('com-01', {
          preRefundAmountPaise: null,
        });
        expect(again.preRefundAmountPaise).toBeNull();
      });

      it('finds a commission by its exact phone hash (and not by another hash)', async () => {
        await w.commissions.create(commission(1));
        expect(
          (await w.commissions.findByPhoneHash('v1:member-hash-1'))?.id,
        ).toBe('com-01');
        // The same digest under another pepper version label is another string.
        expect(
          await w.commissions.findByPhoneHash('v0:member-hash-1'),
        ).toBeNull();
        expect(await w.commissions.findByPhoneHash('nope')).toBeNull();
      });

      it('transition changes the row only if it is still in the expected state', async () => {
        await w.commissions.create(commission(1));
        expect(
          await w.commissions.transition('com-01', 'READY', {
            status: 'APPROVED',
          }),
        ).toBeNull();
        expect((await w.commissions.findById('com-01'))?.status).toBe(
          'ON_HOLD',
        );
        const moved = await w.commissions.transition('com-01', 'ON_HOLD', {
          status: 'FROZEN',
        });
        expect(moved?.status).toBe('FROZEN');
        expect(
          await w.commissions.transition('nope', 'ON_HOLD', {
            status: 'FROZEN',
          }),
        ).toBeNull();
      });

      it('two parallel transitions of one commission: exactly one wins', async () => {
        await w.commissions.create(commission(1));
        const results = await Promise.all([
          w.commissions.transition('com-01', 'ON_HOLD', { status: 'FROZEN' }),
          w.commissions.transition('com-01', 'ON_HOLD', {
            status: 'AWAITING_VERIFICATION',
          }),
        ]);
        expect(results.filter((r) => r !== null)).toHaveLength(1);
      });

      it('listOpen returns only open commissions, in id order, with a cursor', async () => {
        await w.commissions.create(commission(1, { status: 'ON_HOLD' }));
        await w.commissions.create(commission(2, { status: 'APPROVED' }));
        await w.commissions.create(commission(3, { status: 'FROZEN' }));
        await w.commissions.create(commission(4, { status: 'CANCELLED' }));
        await w.commissions.create(commission(5, { status: 'READY' }));
        await w.commissions.create(commission(6, { status: 'IN_REVIEW' }));
        const first = await w.commissions.listOpen({ limit: 2 });
        expect(first.map((c) => c.id)).toEqual(['com-01', 'com-03']);
        const second = await w.commissions.listOpen({
          limit: 10,
          afterId: 'com-03',
        });
        expect(second.map((c) => c.id)).toEqual(['com-05', 'com-06']);
      });

      it('listAgentIdsWithPayable pages the agents with approved, unattached commissions', async () => {
        await w.commissions.create(commission(1, { status: 'ON_HOLD' }));
        expect(
          await w.commissions.listAgentIdsWithPayable({ limit: 10 }),
        ).toEqual([]);
        await w.commissions.create(commission(2, { status: 'APPROVED' }));
        await w.commissions.create(commission(3, { status: 'APPROVED' }));
        await w.commissions.create(commission(7, { status: 'APPROVED' })); // agent-2
        expect(
          await w.commissions.listAgentIdsWithPayable({ limit: 10 }),
        ).toEqual(['agent-1', 'agent-2']);
        expect(
          await w.commissions.listAgentIdsWithPayable({ limit: 1 }),
        ).toEqual(['agent-1']);
        expect(
          await w.commissions.listAgentIdsWithPayable({
            afterAgentId: 'agent-1',
            limit: 10,
          }),
        ).toEqual(['agent-2']);
        // In a payout already: not payable.
        await w.payouts.create(payout(1, { agentId: 'agent-2' }));
        await w.commissions.attachToPayout(['com-07'], 'po-01');
        expect(
          await w.commissions.listAgentIdsWithPayable({ limit: 10 }),
        ).toEqual(['agent-1']);
      });

      it("listPayableByAgent returns only that agent's approved, unattached commissions", async () => {
        await w.commissions.create(commission(1, { status: 'APPROVED' }));
        await w.commissions.create(commission(2, { status: 'ON_HOLD' }));
        await w.commissions.create(commission(3, { status: 'APPROVED' }));
        await w.commissions.create(commission(7, { status: 'APPROVED' })); // agent-2
        await w.payouts.create(payout(1));
        await w.commissions.create(
          commission(4, { status: 'APPROVED', payoutId: 'po-01' }),
        );
        expect(
          (await w.commissions.listPayableByAgent('agent-1')).map((c) => c.id),
        ).toEqual(['com-01', 'com-03']);
        expect(
          (await w.commissions.listByPayout('po-01')).map((c) => c.id),
        ).toEqual(['com-04']);
      });

      it('attaches only approved, unattached commissions to a payout; release and mark-paid act on its own', async () => {
        await w.payouts.create(payout(1));
        await w.payouts.create(payout(2, { period: '2026-12' }));
        await w.commissions.create(commission(1, { status: 'APPROVED' }));
        await w.commissions.create(commission(2, { status: 'ON_HOLD' }));
        await w.commissions.create(commission(3, { status: 'APPROVED' }));
        expect(
          await w.commissions.attachToPayout(
            ['com-01', 'com-02', 'com-03', 'nope'],
            'po-01',
          ),
        ).toBe(2);
        // Already attached: not attached again, not stolen by another payout.
        expect(await w.commissions.attachToPayout(['com-01'], 'po-02')).toBe(0);
        expect((await w.commissions.findById('com-01'))?.payoutId).toBe(
          'po-01',
        );
        expect(await w.commissions.markPaidForPayout('po-01', at(90))).toBe(2);
        expect(await w.commissions.findById('com-01')).toMatchObject({
          status: 'PAID',
          paidAt: at(90),
        });
        expect((await w.commissions.findById('com-02'))?.status).toBe(
          'ON_HOLD',
        );
        expect(await w.commissions.releaseFromPayout('po-01')).toBe(2);
        expect((await w.commissions.findById('com-01'))?.payoutId).toBeNull();
      });

      describe('listPage', () => {
        const seed = async () => {
          await w.commissions.create(commission(1));
          await w.commissions.create(commission(2, { status: 'APPROVED' }));
          await w.commissions.create(commission(3, { createdAt: at(10) }));
          await w.commissions.create(commission(4, { createdAt: at(10) }));
          await w.commissions.create(commission(7, { createdAt: at(11) })); // agent-2
        };

        it('is newest first, ties by id descending, and filters', async () => {
          await seed();
          expect(
            (await w.commissions.listPage({}, { limit: 10 })).map((c) => c.id),
          ).toEqual(['com-07', 'com-04', 'com-03', 'com-02', 'com-01']);
          expect(
            (
              await w.commissions.listPage(
                { agentId: 'agent-1' },
                { limit: 10 },
              )
            ).map((c) => c.id),
          ).toEqual(['com-04', 'com-03', 'com-02', 'com-01']);
          expect(
            (
              await w.commissions.listPage(
                { status: 'APPROVED' },
                { limit: 10 },
              )
            ).map((c) => c.id),
          ).toEqual(['com-02']);
        });

        it('pages with a cursor without skipping or repeating a row', async () => {
          await seed();
          const seen: string[] = [];
          let after: { at: Date; id: string } | undefined;
          for (let i = 0; i < 6; i++) {
            const page = await w.commissions.listPage({}, { limit: 2, after });
            if (page.length === 0) break;
            seen.push(...page.map((c) => c.id));
            const last = page[page.length - 1];
            after = { at: last.createdAt, id: last.id };
          }
          expect(seen).toEqual([
            'com-07',
            'com-04',
            'com-03',
            'com-02',
            'com-01',
          ]);
        });
      });
    });

    describe('AgentLedgerRepository', () => {
      const credit = (n: number, amount = 848) => {
        return buildCreditEntry({
          agentId: 'agent-1',
          commissionId: `com-${String(n).padStart(2, '0')}`,
          amountPaise: amount,
          calcType: 'PERCENTAGE',
          value: 1000,
          ruleSnapshot: { calcType: 'PERCENTAGE', value: 1000, holdDays: 14 },
        });
      };

      beforeEach(async () => {
        await w.commissions.create(commission(1));
        await w.commissions.create(commission(2));
        await w.payouts.create(payout(1));
      });

      it('appends an entry and finds it by key, with its rule snapshot', async () => {
        expect(await w.ledger.append(credit(1))).toEqual({ inserted: true });
        const stored = await w.ledger.findByKey('credit:com-01');
        expect(stored).toMatchObject({
          agentId: 'agent-1',
          type: 'CREDIT',
          amountPaise: 848,
          commissionId: 'com-01',
          calcType: 'PERCENTAGE',
          value: 1000,
          ruleSnapshot: { calcType: 'PERCENTAGE', value: 1000, holdDays: 14 },
          refundId: null,
          payoutId: null,
          reason: null,
        });
        expect(typeof stored?.id).toBe('string');
        expect(stored?.createdAt).toBeInstanceOf(Date);
        expect(await w.ledger.findByKey('nope')).toBeNull();
      });

      it('the same idempotency key again appends nothing', async () => {
        await w.ledger.append(credit(1));
        expect(await w.ledger.append(credit(1, 99999))).toEqual({
          inserted: false,
        });
        expect((await w.ledger.listByAgent('agent-1')).length).toBe(1);
        expect((await w.ledger.findByKey('credit:com-01'))?.amountPaise).toBe(
          848,
        );
      });

      it('two parallel appends of one key: exactly one is inserted', async () => {
        const results = await Promise.all([
          w.ledger.append(credit(1)),
          w.ledger.append(credit(1)),
        ]);
        expect(results.filter((r) => r.inserted)).toHaveLength(1);
        expect((await w.ledger.listByAgent('agent-1')).length).toBe(1);
      });

      it('the balance is the sum of signed entries and may be negative', async () => {
        expect(await w.ledger.balance('agent-1')).toBe(0);
        await w.ledger.append(credit(1, 1000));
        await w.ledger.append(
          buildReversalEntry({
            agentId: 'agent-1',
            commissionId: 'com-01',
            refundId: 'rf-1',
            reversalPaise: 400,
          }),
        );
        expect(await w.ledger.balance('agent-1')).toBe(600);
        await w.ledger.append(
          buildPayoutDebitEntry({
            agentId: 'agent-1',
            payoutId: 'po-01',
            amountPaise: 1500,
          }),
        );
        expect(await w.ledger.balance('agent-1')).toBe(-900);
        expect(await w.ledger.balance('agent-2')).toBe(0);
      });

      it("lists only the agent's entries, oldest first, and keeps an adjustment reason", async () => {
        await w.ledger.append(credit(1));
        await w.ledger.append(
          buildAdjustmentEntry({
            agentId: 'agent-1',
            amountPaise: -50,
            reason: 'goodwill correction',
            idempotencyKey: 'adj:1',
          }),
        );
        const entries = await w.ledger.listByAgent('agent-1');
        expect(entries.map((e) => e.idempotencyKey)).toEqual([
          'credit:com-01',
          'adj:1',
        ]);
        expect(entries[1]).toMatchObject({
          type: 'ADJUSTMENT',
          reason: 'goodwill correction',
          amountPaise: -50,
        });
        expect(await w.ledger.listByAgent('agent-2')).toEqual([]);
      });

      it('a replayed append inside a transaction does not break the transaction', async () => {
        await w.ledger.append(credit(1));
        await w.uow.run(async (tx) => {
          expect(await w.ledger.append(credit(1), tx)).toEqual({
            inserted: false,
          });
          // Still usable after the duplicate.
          expect(await w.ledger.append(credit(2), tx)).toEqual({
            inserted: true,
          });
        });
        expect((await w.ledger.listByAgent('agent-1')).length).toBe(2);
      });

      it('entries appended in a failed transaction are undone with it', async () => {
        await expect(
          w.uow.run(async (tx) => {
            await w.ledger.append(credit(1), tx);
            throw new Error('boom');
          }),
        ).rejects.toThrow('boom');
        expect(await w.ledger.balance('agent-1')).toBe(0);
      });
    });

    describe('AgentPayoutRepository', () => {
      it('creates and finds by id, by agent and period, and by reference', async () => {
        const created = await w.payouts.create(payout(1));
        expect(created).toEqual(payout(1));
        expect(await w.payouts.findById('po-01')).toEqual(created);
        expect(
          await w.payouts.findActiveByAgentPeriod('agent-1', '2026-11'),
        ).toEqual(created);
        expect(
          await w.payouts.findActiveByAgentPeriod('agent-1', '2026-12'),
        ).toBeNull();
        expect(await w.payouts.findByReference('UTR1')).toBeNull();
        expect(await w.payouts.findById('nope')).toBeNull();
      });

      it('one non-cancelled payout per agent and period; a cancel frees the period', async () => {
        await w.payouts.create(payout(1));
        await expect(w.payouts.create(payout(2))).rejects.toEqual(
          conflict('DUPLICATE_PAYOUT'),
        );
        // Another agent, or another period, is fine.
        await w.payouts.create(payout(3, { agentId: 'agent-2' }));
        await w.payouts.create(payout(4, { period: '2026-12' }));
        await expect(
          w.payouts.create(payout(5, { id: 'po-01', period: '2027-01' })),
        ).rejects.toEqual(conflict('DUPLICATE_ID'));
        await w.payouts.cancel('po-01', {
          reason: 'wrong account',
          at: at(20),
        });
        await expect(w.payouts.create(payout(6))).resolves.toMatchObject({
          id: 'po-06',
        });
        expect(
          (await w.payouts.findActiveByAgentPeriod('agent-1', '2026-11'))?.id,
        ).toBe('po-06');
      });

      it('markPaid moves CREATED to PAID once; a second call changes nothing', async () => {
        await w.payouts.create(payout(1));
        const paid = await w.payouts.markPaid('po-01', {
          reference: 'UTR0001',
          paidAt: at(40),
        });
        expect(paid).toMatchObject({
          status: 'PAID',
          reference: 'UTR0001',
          paidAt: at(40),
        });
        expect(
          await w.payouts.markPaid('po-01', {
            reference: 'UTR0002',
            paidAt: at(50),
          }),
        ).toBeNull();
        expect(await w.payouts.findById('po-01')).toMatchObject({
          reference: 'UTR0001',
          paidAt: at(40),
        });
        expect((await w.payouts.findByReference('UTR0001'))?.id).toBe('po-01');
        expect(
          await w.payouts.markPaid('nope', { reference: 'X', paidAt: at(1) }),
        ).toBeNull();
      });

      it('a payment reference can be used once', async () => {
        await w.payouts.create(payout(1));
        await w.payouts.create(payout(2, { period: '2026-12' }));
        await w.payouts.markPaid('po-01', {
          reference: 'UTR0001',
          paidAt: at(40),
        });
        await expect(
          w.payouts.markPaid('po-02', { reference: 'UTR0001', paidAt: at(41) }),
        ).rejects.toEqual(conflict('DUPLICATE_PAYOUT_REFERENCE'));
        expect((await w.payouts.findById('po-02'))?.status).toBe('CREATED');
      });

      it('cancel works only from CREATED', async () => {
        await w.payouts.create(payout(1));
        await w.payouts.create(payout(2, { period: '2026-12' }));
        const cancelled = await w.payouts.cancel('po-01', {
          reason: 'wrong account',
          at: at(20),
        });
        expect(cancelled).toMatchObject({
          status: 'CANCELLED',
          cancelReason: 'wrong account',
          cancelledAt: at(20),
        });
        expect(
          await w.payouts.cancel('po-01', { reason: 'again', at: at(21) }),
        ).toBeNull();
        await w.payouts.markPaid('po-02', {
          reference: 'UTR9',
          paidAt: at(30),
        });
        expect(
          await w.payouts.cancel('po-02', { reason: 'too late', at: at(31) }),
        ).toBeNull();
        expect((await w.payouts.findById('po-02'))?.status).toBe('PAID');
      });

      it('two parallel markPaid calls on one payout: exactly one wins', async () => {
        await w.payouts.create(payout(1));
        const results = await Promise.allSettled([
          w.payouts.markPaid('po-01', { reference: 'UTR-A', paidAt: at(40) }),
          w.payouts.markPaid('po-01', { reference: 'UTR-B', paidAt: at(40) }),
        ]);
        const won = results.filter(
          (r) => r.status === 'fulfilled' && r.value !== null,
        );
        expect(won).toHaveLength(1);
      });

      it('lists newest first with filters and a cursor', async () => {
        await w.payouts.create(payout(1));
        await w.payouts.create(
          payout(2, { period: '2026-12', createdAt: at(10) }),
        );
        await w.payouts.create(
          payout(3, { agentId: 'agent-2', createdAt: at(10) }),
        );
        await w.payouts.create(
          payout(4, { period: '2027-01', createdAt: at(12) }),
        );
        expect(
          (await w.payouts.listPage({}, { limit: 10 })).map((p) => p.id),
        ).toEqual(['po-04', 'po-03', 'po-02', 'po-01']);
        expect(
          (await w.payouts.listPage({ agentId: 'agent-2' }, { limit: 10 })).map(
            (p) => p.id,
          ),
        ).toEqual(['po-03']);
        expect(
          (await w.payouts.listPage({ period: '2026-12' }, { limit: 10 })).map(
            (p) => p.id,
          ),
        ).toEqual(['po-02']);
        const page = await w.payouts.listPage(
          {},
          { limit: 10, after: { at: at(10), id: 'po-03' } },
        );
        expect(page.map((p) => p.id)).toEqual(['po-02', 'po-01']);
      });
    });

    describe('one transaction across the repositories', () => {
      it('commission, ledger entry, payout and attachment commit or roll back together', async () => {
        await w.commissions.create(commission(1, { status: 'APPROVED' }));
        await expect(
          w.uow.run(async (tx) => {
            await w.payouts.create(payout(1), tx);
            await w.commissions.attachToPayout(['com-01'], 'po-01', tx);
            await w.ledger.append(
              buildPayoutDebitEntry({
                agentId: 'agent-1',
                payoutId: 'po-01',
                amountPaise: 848,
              }),
              tx,
            );
            throw new Error('boom');
          }),
        ).rejects.toThrow('boom');
        expect(await w.payouts.findById('po-01')).toBeNull();
        expect((await w.commissions.findById('com-01'))?.payoutId).toBeNull();
        expect(await w.ledger.balance('agent-1')).toBe(0);

        await w.uow.run(async (tx) => {
          await w.payouts.create(payout(1), tx);
          await w.commissions.attachToPayout(['com-01'], 'po-01', tx);
          await w.ledger.append(
            buildPayoutDebitEntry({
              agentId: 'agent-1',
              payoutId: 'po-01',
              amountPaise: 848,
            }),
            tx,
          );
        });
        expect((await w.commissions.findById('com-01'))?.payoutId).toBe(
          'po-01',
        );
        expect(await w.ledger.balance('agent-1')).toBe(-848);
      });
    });

    it('uses dates in whole milliseconds and a day is a day', () => {
      // Guards the helpers above: the database keeps milliseconds.
      expect(at(1440).getTime() - at(0).getTime()).toBe(DAY);
    });
  });
}
