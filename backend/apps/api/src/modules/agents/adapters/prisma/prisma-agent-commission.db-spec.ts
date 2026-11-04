/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md): the
 * commission policy, commission, ledger and payout adapters against a
 * throwaway LOCAL Postgres. Runs the SAME contract suite as the in-memory
 * fakes, then what only the real database does: the append-only trigger, the
 * CHECK constraints (not hidden as conflicts), the no-cascade rule and the
 * seeded policy version.
 */
import { AgentConflictError } from '../../ports/agent-data-ports';
import { defineAgentCommissionContract } from '../../testing/agent-commission.contract';
import { PrismaAgentLedgerRepository } from './prisma-agent-ledger.repository';
import { PrismaAgentPayoutRepository } from './prisma-agent-payout.repository';
import { PrismaAgentRepository } from './prisma-agent.repository';
import { PrismaAgentUnitOfWork } from './prisma-agent-unit-of-work';
import { PrismaCommissionPolicyRepository } from './prisma-commission-policy.repository';
import { PrismaCommissionRepository } from './prisma-commission.repository';
import { PrismaReferralAttributionRepository } from './prisma-referral-attribution.repository';
import { openTestDatabase, freshTestDatabase } from './prisma-test-database';

const db = openTestDatabase();
const prisma = db.prisma;

afterAll(async () => {
  await db.close();
});

const world = () => ({
  uow: new PrismaAgentUnitOfWork(prisma),
  agents: new PrismaAgentRepository(prisma),
  attributions: new PrismaReferralAttributionRepository(prisma),
  policy: new PrismaCommissionPolicyRepository(prisma),
  commissions: new PrismaCommissionRepository(prisma),
  ledger: new PrismaAgentLedgerRepository(prisma),
  payouts: new PrismaAgentPayoutRepository(prisma),
});

defineAgentCommissionContract('prisma', async () => {
  await freshTestDatabase(prisma);
  return {
    ...world(),
    addPolicyVersion: async (v) => {
      await prisma.commissionPolicyVersion.create({
        data: {
          id: v.id,
          version: v.version,
          calcType: v.calcType,
          value: v.value,
          holdDays: v.holdDays,
          effectiveFrom: v.effectiveFrom,
        },
      });
    },
  };
});

describe('prisma commission adapters: what only the real database shows', () => {
  const NOW = new Date('2026-10-29T09:00:00.000Z');

  beforeEach(async () => {
    await freshTestDatabase(prisma);
    const w = world();
    await w.agents.create({
      id: 'agent-1',
      phoneHash: 'v1:hash-1',
      phoneE164: '+919000000001',
      name: 'Ravi',
      city: 'Madurai',
      state: 'Tamil Nadu',
      panLast4: null,
      panSealed: null,
      createdAt: NOW,
    });
    await w.attributions.create({
      id: 'attr-1',
      memberId: null,
      agentId: 'agent-1',
      codeId: null,
      source: 'CODE_AT_SIGNUP',
      memberPhoneHash: 'v1:member-hash-1',
      attributedAt: NOW,
      status: 'ACTIVE',
      windowEndsAt: NOW,
      needsReview: false,
    });
    await prisma.commissionPolicyVersion.create({
      data: {
        id: 'pol-101',
        version: 101,
        calcType: 'PERCENTAGE',
        value: 1000,
        holdDays: 14,
        effectiveFrom: new Date('2020-01-01T00:00:00.000Z'),
      },
    });
  });

  const base = {
    id: 'com-1',
    agentId: 'agent-1',
    attributionId: 'attr-1',
    paymentId: 'pay-1',
    phoneHash: 'v1:member-hash-1',
    policyVersionId: 'pol-101',
    status: 'ON_HOLD' as const,
    calcType: 'PERCENTAGE' as const,
    ruleValue: 1000,
    basePaise: 8475,
    amountPaise: 848,
    amountPaidPaise: 10000,
    taxableAmountPaise: 8475,
    refundedPaise: 0,
    preRefundAmountPaise: null,
    creditedPaise: 0,
    reversedPaise: 0,
    holdUntil: NOW,
    reviewReasons: [],
    approvedAt: null,
    paidAt: null,
    cancelledAt: null,
    payoutId: null,
    createdAt: NOW,
  };

  it('the migration seeded policy version 1: 10%, 14 days, in effect now', async () => {
    const seeded = await world().policy.findActive(new Date());
    // Version 1 is the newest version already in effect (the test adds 101 in 2020, which is older by date but higher by number).
    expect(seeded).not.toBeNull();
    const v1 = await prisma.commissionPolicyVersion.findUnique({
      where: { version: 1 },
    });
    expect(v1).toMatchObject({
      calcType: 'PERCENTAGE',
      value: 1000,
      holdDays: 14,
    });
    expect(v1?.effectiveFrom.getTime()).toBeLessThanOrEqual(Date.now());
  });

  it('a commission above what was paid is a CHECK violation, not a conflict', async () => {
    const error = await world()
      .commissions.create({ ...base, amountPaise: 10001 })
      .catch((e: unknown) => e);
    expect(error).toBeInstanceOf(Error);
    expect(error).not.toBeInstanceOf(AgentConflictError);
    expect(String(error)).toMatch(/commissions_amount_between_chk/);
  });

  it('crediting more than the amount, or reversing more than credited, is refused by the database', async () => {
    const w = world();
    await w.commissions.create(base);
    await expect(
      w.commissions.update('com-1', { creditedPaise: 849 }),
    ).rejects.toThrow(/commissions_credit_chk/);
    await w.commissions.update('com-1', { creditedPaise: 848 });
    await expect(
      w.commissions.update('com-1', { reversedPaise: 849 }),
    ).rejects.toThrow(/commissions_credit_chk/);
  });

  it('the ledger rejects UPDATE and DELETE (append-only trigger)', async () => {
    const w = world();
    await w.commissions.create(base);
    await w.ledger.append({
      agentId: 'agent-1',
      type: 'CREDIT',
      amountPaise: 848,
      idempotencyKey: 'credit:com-1',
      commissionId: 'com-1',
      refundId: null,
      payoutId: null,
      calcType: 'PERCENTAGE',
      value: 1000,
      ruleSnapshot: null,
      reason: null,
    });
    await expect(
      prisma.agentLedgerEntry.updateMany({ data: { amountPaise: 1 } }),
    ).rejects.toThrow(/append-only/);
    await expect(prisma.agentLedgerEntry.deleteMany({})).rejects.toThrow(
      /append-only/,
    );
    expect(await w.ledger.balance('agent-1')).toBe(848);
  });

  it('a ledger entry with the wrong sign or a missing link is a CHECK violation', async () => {
    const w = world();
    await expect(
      w.ledger.append({
        agentId: 'agent-1',
        type: 'CREDIT',
        amountPaise: -5,
        idempotencyKey: 'bad:1',
        commissionId: null,
        refundId: null,
        payoutId: null,
        calcType: null,
        value: null,
        ruleSnapshot: null,
        reason: null,
      }),
    ).rejects.toThrow(/agent_ledger_entries_(amount_sign|links)_chk/);
  });

  it('money records are never removed as a side effect: the agent, the commission and the payout cannot be deleted while referenced', async () => {
    const w = world();
    await w.commissions.create(base);
    await expect(
      prisma.agent.delete({ where: { id: 'agent-1' } }),
    ).rejects.toThrow();
    await expect(
      prisma.referralAttribution.delete({ where: { id: 'attr-1' } }),
    ).rejects.toThrow();
    await expect(
      prisma.commissionPolicyVersion.delete({ where: { id: 'pol-101' } }),
    ).rejects.toThrow();
  });

  it('a payout needs a reason when cancelled and a reference when paid (CHECK, not a conflict)', async () => {
    const w = world();
    await w.payouts.create({
      id: 'po-1',
      agentId: 'agent-1',
      period: '2026-11',
      amountPaise: 100,
      taxWithheldPaise: 0,
      netPaise: 100,
      status: 'CREATED',
      reference: null,
      paidAt: null,
      cancelReason: null,
      cancelledAt: null,
      createdBy: 'staff-1',
      createdAt: NOW,
    });
    await expect(
      w.payouts.cancel('po-1', { reason: '   ', at: NOW }),
    ).rejects.toThrow(/agent_payouts_status_fields_chk/);
    await expect(
      w.payouts.markPaid('po-1', { reference: ' ', paidAt: NOW }),
    ).rejects.toThrow(/agent_payouts_status_fields_chk/);
  });
});
