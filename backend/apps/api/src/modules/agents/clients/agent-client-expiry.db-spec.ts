/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md): the
 * daily client expiry on the Prisma adapters and a throwaway LOCAL
 * Postgres: it catches up after a gap, deletes the PII, audits once per
 * draft, and a second run changes nothing.
 */
import { PrismaAgentClientConsentCodeStore } from '../adapters/prisma/prisma-agent-client-consent-code.store';
import { PrismaAgentClientDraftRepository } from '../adapters/prisma/prisma-agent-client-draft.repository';
import { PrismaAgentUnitOfWork } from '../adapters/prisma/prisma-agent-unit-of-work';
import { PrismaTestAudit } from '../adapters/prisma/prisma-test-audit';
import {
  freshTestDatabase,
  openTestDatabase,
} from '../adapters/prisma/prisma-test-database';
import { AgentClientExpiryService } from './agent-client-expiry.service';

const db = openTestDatabase();
const prisma = db.prisma;

afterAll(() => db.close());
beforeEach(() => freshTestDatabase(prisma));

const T0 = new Date('2026-11-03T09:00:00.000Z');
const DAY = 86_400_000;

const expiry = () =>
  new AgentClientExpiryService({
    drafts: new PrismaAgentClientDraftRepository(prisma),
    codes: new PrismaAgentClientConsentCodeStore(prisma),
    uow: new PrismaAgentUnitOfWork(prisma),
    audit: new PrismaTestAudit(prisma),
  });

async function seed() {
  await prisma.agent.create({
    data: {
      id: 'agent-1',
      phone: '+919876543210',
      phoneHash: 'v1:agent-1',
      name: 'Ravi Kumar',
      city: 'Madurai',
      state: 'Tamil Nadu',
      status: 'ACTIVE',
    },
  });
  const drafts = new PrismaAgentClientDraftRepository(prisma);
  for (const [n, days] of [
    [1, 1],
    [2, 2],
    [3, 30],
  ] as const) {
    await drafts.create({
      id: `draft-${n}`,
      agentId: 'agent-1',
      phoneHash: `v1:client-${n}`,
      phoneSealed: `sealed-phone-${n}`,
      phoneMasked: '+91 90***001',
      displayName: 'Priya S.',
      detailsSealed: `sealed-details-${n}`,
      expiresAt: new Date(T0.getTime() + days * DAY),
      createdAt: T0,
    });
  }
}

describe('AgentClientExpiryService on the real database', () => {
  it('after a two-day gap closes both due drafts, wipes their PII, audits each once; a second run does nothing', async () => {
    await seed();
    const at = new Date(T0.getTime() + 3 * DAY);
    await expect(expiry().runDailyExpiry(at, 1)).resolves.toEqual({
      expired: 2,
      closedForTerminatedAgents: 0,
      codesPurged: 0,
    });
    const rows = await prisma.agentClientDraft.findMany({
      orderBy: { id: 'asc' },
    });
    expect(
      rows.map((r) => [r.id, r.status, r.phoneSealed, r.detailsSealed]),
    ).toEqual([
      ['draft-1', 'EXPIRED', null, null],
      ['draft-2', 'EXPIRED', null, null],
      ['draft-3', 'DRAFT', 'sealed-phone-3', 'sealed-details-3'],
    ]);
    expect(
      await prisma.auditLog.count({
        where: { action: 'AGENT_CLIENT_DRAFT_EXPIRED' },
      }),
    ).toBe(2);

    await expect(expiry().runDailyExpiry(at, 1)).resolves.toEqual({
      expired: 0,
      closedForTerminatedAgents: 0,
      codesPurged: 0,
    });
    expect(await prisma.auditLog.count()).toBe(2);
  });

  it("closes a TERMINATED agent's open drafts", async () => {
    await seed();
    await prisma.agent.update({
      where: { id: 'agent-1' },
      data: { status: 'TERMINATED' },
    });
    const report = await expiry().runDailyExpiry(T0, 500);
    expect(report.closedForTerminatedAgents).toBe(3);
    expect(
      await prisma.agentClientDraft.count({
        where: { closedReason: 'AGENT_TERMINATED', phoneSealed: null },
      }),
    ).toBe(3);
  });
});
