/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md): the Prisma
 * adapters against a throwaway LOCAL Postgres, running the SAME contract
 * suite as the in-memory fakes, plus what only a real database can show.
 */
import { AgentConflictError } from '../../ports/agent-data-ports';
import { defineAgentRepositoryContract } from '../../testing/agent-repositories.contract';
import { PrismaAgentPayoutDetailsRepository } from './prisma-agent-payout-details.repository';
import { PrismaAgentRefreshTokenRepository } from './prisma-agent-refresh-token.repository';
import { PrismaAgentRepository } from './prisma-agent.repository';
import { PrismaAgentUnitOfWork } from './prisma-agent-unit-of-work';
import { PrismaReferralCodeRepository } from './prisma-referral-code.repository';
import { PrismaTestAudit } from './prisma-test-audit';
import { openTestDatabase, truncateAgentTables } from './prisma-test-database';

const db = openTestDatabase();
const prisma = db.prisma;

afterAll(() => db.close());

function makeWorld() {
  return {
    uow: new PrismaAgentUnitOfWork(prisma),
    agents: new PrismaAgentRepository(prisma),
    codes: new PrismaReferralCodeRepository(prisma),
    tokens: new PrismaAgentRefreshTokenRepository(prisma),
    payout: new PrismaAgentPayoutDetailsRepository(prisma),
    audit: new PrismaTestAudit(prisma),
  };
}

defineAgentRepositoryContract('prisma', async () => {
  await truncateAgentTables(prisma);
  return {
    ...makeWorld(),
    auditCount: () => prisma.auditLog.count(),
    cleanup: () => truncateAgentTables(prisma),
  };
});

describe('prisma adapters: what only the real database shows', () => {
  const agent = {
    id: 'agent-1',
    phoneHash: 'v1:hash-1',
    phoneE164: '+919000000001',
    name: 'Ravi',
    city: 'Madurai',
    state: 'Tamil Nadu',
    panLast4: null,
    panSealed: null,
    createdAt: new Date('2026-10-29T09:00:00.000Z'),
  };

  beforeEach(() => truncateAgentTables(prisma));
  afterAll(() => truncateAgentTables(prisma));

  it('refuses the same phone under a different hash as DUPLICATE_PHONE_HASH', async () => {
    const { agents } = makeWorld();
    await agents.create(agent);
    await expect(
      agents.create({ ...agent, id: 'agent-2', phoneHash: 'v1:hash-2' }),
    ).rejects.toEqual(new AgentConflictError('DUPLICATE_PHONE_HASH'));
  });

  it('does not hide a CHECK violation as a conflict (a bad code format is a caller bug)', async () => {
    const { agents, codes } = makeWorld();
    await agents.create(agent);
    await expect(
      codes.create({
        id: 'code-1',
        agentId: 'agent-1',
        code: 'XX',
        isPrimary: false,
        isActive: true,
        createdAt: agent.createdAt,
      }),
    ).rejects.not.toBeInstanceOf(AgentConflictError);
  });

  it('a rejected agent needs a reason (the CHECK is not hidden either)', async () => {
    const { agents } = makeWorld();
    await agents.create(agent);
    await expect(
      agents.update('agent-1', { status: 'REJECTED', rejectionReason: ' ' }),
    ).rejects.not.toBeInstanceOf(AgentConflictError);
  });

  it('deleting an agent deletes its codes, tokens and payout details (cascade)', async () => {
    const { agents, codes, tokens, payout } = makeWorld();
    await agents.create(agent);
    await codes.create({
      id: 'code-1',
      agentId: 'agent-1',
      code: 'NM7K2P9X',
      isPrimary: true,
      isActive: true,
      createdAt: agent.createdAt,
    });
    await tokens.create({
      id: 'token-1',
      agentId: 'agent-1',
      tokenHash: 'th',
      expiresAt: agent.createdAt,
      revokedAt: null,
      createdAt: agent.createdAt,
    });
    await payout.save({
      agentId: 'agent-1',
      method: 'UPI',
      detailsSealed: 's',
      display: 'd',
      verifiedAt: null,
      changedAt: agent.createdAt,
    });
    await prisma.agent.delete({ where: { id: 'agent-1' } });
    expect(await codes.listByAgent('agent-1')).toEqual([]);
    expect(await tokens.findByHash('th')).toBeNull();
    expect(await payout.find('agent-1')).toBeNull();
  });

  it('a write with a finished tx is refused, not sent outside the transaction', async () => {
    const { uow, agents } = makeWorld();
    const leaked = await uow.run((tx) => Promise.resolve(tx));
    await expect(agents.create(agent, leaked)).rejects.toThrow(
      'The transaction has already finished.',
    );
    expect(await agents.findById('agent-1')).toBeNull();
  });

  it('passes the transaction options to Prisma (a too-short timeout aborts and rolls back)', async () => {
    const { agents } = makeWorld();
    const uow = new PrismaAgentUnitOfWork(prisma, { timeoutMs: 50 });
    await expect(
      uow.run(async (tx) => {
        await agents.create(agent, tx);
        await new Promise((resolve) => setTimeout(resolve, 400));
      }),
    ).rejects.toThrow();
    expect(await agents.findById('agent-1')).toBeNull();
  });
});
