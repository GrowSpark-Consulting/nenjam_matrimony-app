/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md): the admin
 * read port against a throwaway LOCAL Postgres.
 */
import { PrismaAgentAdminRead } from './prisma-agent-admin-read';
import { PrismaAgentRepository } from './prisma-agent.repository';
import { PrismaReferralCodeRepository } from './prisma-referral-code.repository';
import { PrismaAgentPayoutDetailsRepository } from './prisma-agent-payout-details.repository';
import { openTestDatabase, truncateAgentTables } from './prisma-test-database';

const db = openTestDatabase();
const prisma = db.prisma;

afterAll(async () => {
  await truncateAgentTables(prisma);
  await db.close();
});
beforeEach(() => truncateAgentTables(prisma));

const read = new PrismaAgentAdminRead(prisma);
const agents = new PrismaAgentRepository(prisma);
const codes = new PrismaReferralCodeRepository(prisma);
const details = new PrismaAgentPayoutDetailsRepository(prisma);

const T0 = new Date('2026-10-29T09:00:00.000Z');
const id = (n: number) =>
  `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`;

async function seed(n: number, name: string, minutes: number) {
  await agents.create({
    id: id(n),
    phoneHash: `v1:hash-${n}`,
    phoneE164: `+9190000000${String(n).padStart(2, '0')}`,
    name,
    city: 'Madurai',
    state: 'Tamil Nadu',
    panLast4: null,
    panSealed: null,
    createdAt: new Date(T0.getTime() + minutes * 60_000),
  });
}

describe('PrismaAgentAdminRead', () => {
  it('lists newest first with the primary code and the payout-details flag, filtered', async () => {
    await seed(1, 'Ravi Kumar', 1);
    await seed(2, 'ravi shankar', 2);
    await seed(3, 'Mala', 3);
    await agents.update(id(3), { status: 'ACTIVE' });
    await codes.create({
      id: 'c-1',
      agentId: id(3),
      code: 'NM7K2P9X',
      isPrimary: true,
      isActive: true,
      createdAt: T0,
    });
    await codes.create({
      id: 'c-2',
      agentId: id(3),
      code: 'NM7K2P9Y',
      isPrimary: false,
      isActive: true,
      createdAt: T0,
    });
    await details.save({
      agentId: id(3),
      method: 'UPI',
      detailsSealed: 'v1:sealed',
      display: 'r***@okbank',
      verifiedAt: T0,
      changedAt: T0,
    });
    const rows = await read.listAgents({}, { limit: 10 });
    expect(rows.map((r) => r.agent.name)).toEqual([
      'Mala',
      'ravi shankar',
      'Ravi Kumar',
    ]);
    expect(rows[0]).toMatchObject({
      primaryCode: 'NM7K2P9X',
      payoutDetailsVerified: true,
    });
    expect(rows[1]).toMatchObject({
      primaryCode: null,
      payoutDetailsVerified: false,
    });
    expect(rows[0].updatedAt).toBeInstanceOf(Date);
    const names = async (filter: Parameters<typeof read.listAgents>[0]) =>
      (await read.listAgents(filter, { limit: 10 })).map((r) => r.agent.name);
    expect(await names({ namePrefix: 'RAVI' })).toEqual([
      'ravi shankar',
      'Ravi Kumar',
    ]);
    expect(await names({ status: 'ACTIVE' })).toEqual(['Mala']);
    expect(await names({ ids: [id(1)] })).toEqual(['Ravi Kumar']);
    expect(await names({ phoneHashes: ['v0:old', 'v1:hash-2'] })).toEqual([
      'ravi shankar',
    ]);
    expect(
      (
        await read.listAgents(
          {},
          {
            limit: 10,
            after: { at: new Date(T0.getTime() + 2 * 60_000), id: id(2) },
          },
        )
      ).map((r) => r.agent.name),
    ).toEqual(['Ravi Kumar']);
    expect(
      await read.findAgentRow('11111111-1111-4111-8111-999999999999'),
    ).toBeNull();
  });

  it('counts every status, unverified payout details and referrals needing review', async () => {
    await seed(1, 'A', 1);
    await seed(2, 'B', 2);
    await agents.update(id(2), { status: 'ACTIVE' });
    await details.save({
      agentId: id(2),
      method: 'UPI',
      detailsSealed: 'v1:s',
      display: 'd',
      verifiedAt: null,
      changedAt: T0,
    });
    await prisma.referralAttribution.create({
      data: {
        id: 'attr-1',
        phoneHash: 'v1:m',
        agentId: id(2),
        source: 'CODE_AT_SIGNUP',
        windowEndsAt: T0,
        needsReview: true,
      },
    });
    expect(await read.summary()).toEqual({
      byStatus: {
        PENDING_APPROVAL: 1,
        ACTIVE: 1,
        REJECTED: 0,
        SUSPENDED: 0,
        TERMINATED: 0,
      },
      payoutDetailsAwaitingVerification: 1,
      referralsNeedingReview: 1,
    });
  });

  it("reads only this agent's status changes from the audit log, oldest first", async () => {
    await seed(1, 'A', 1);
    const row = (action: string, entityId: string, at: number, extra = {}) =>
      prisma.auditLog.create({
        data: {
          actorId: 'staff-1',
          actorType: 'STAFF',
          action,
          entity: 'Agent',
          entityId,
          reason: `why ${action}`,
          before: { status: 'PENDING_APPROVAL' },
          after: { status: action === 'agent.reject' ? 'REJECTED' : 'ACTIVE' },
          createdAt: new Date(T0.getTime() + at * 60_000),
          ...extra,
        },
      });
    await row('agent.approve', id(1), 2);
    await row('agent.reject', id(1), 1);
    await row('agent.approve', id(2), 3); // another agent
    await row('agent.pii.reveal', id(1), 4); // not a status change
    await row('agent.pause', id(1), 5, { before: null }); // incomplete row
    const history = await read.statusHistory(id(1));
    expect(history).toEqual([
      expect.objectContaining({
        from: 'PENDING_APPROVAL',
        to: 'REJECTED',
        reason: 'why agent.reject',
        actorType: 'STAFF',
      }),
      expect.objectContaining({
        from: 'PENDING_APPROVAL',
        to: 'ACTIVE',
        reason: 'why agent.approve',
      }),
    ]);
  });
});
