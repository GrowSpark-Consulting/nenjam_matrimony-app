/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md): the
 * client draft repository and consent-code store against a throwaway LOCAL
 * Postgres, running the SAME contract suite as the in-memory fakes, plus
 * what only a real database can show (locks, the foreign keys, the trigger).
 */
import type { AgentStatus } from '../../agent/agent-status';
import { AgentConflictError } from '../../ports/agent-data-ports';
import { defineAgentClientContract } from '../../testing/agent-clients.contract';
import { PrismaAgentClientConsentCodeStore } from './prisma-agent-client-consent-code.store';
import { PrismaAgentClientDraftRepository } from './prisma-agent-client-draft.repository';
import { PrismaAgentUnitOfWork } from './prisma-agent-unit-of-work';
import { openTestDatabase, freshTestDatabase } from './prisma-test-database';

const db = openTestDatabase();
const prisma = db.prisma;

afterAll(() => db.close());

const T0 = new Date('2026-11-03T09:00:00.000Z');
const at = (minutes: number) => new Date(T0.getTime() + minutes * 60_000);

let agentCount = 0;
const seedAgent = async (id: string, status: AgentStatus = 'ACTIVE') => {
  agentCount += 1;
  await prisma.agent.create({
    data: {
      id,
      phone: `+91900000${String(agentCount).padStart(4, '0')}`,
      phoneHash: `v1:agent-${id}`,
      name: `Agent ${agentCount}`,
      city: 'Madurai',
      state: 'Tamil Nadu',
      status,
    },
  });
};
const seedMember = async (id: string) => {
  await prisma.user.create({
    data: { id, firebaseUid: `fb-${id}`, email: `${id}@example.invalid` },
  });
};
const seedAttribution = async (
  id: string,
  agentId: string,
  memberId: string,
) => {
  await prisma.referralAttribution.create({
    data: {
      id,
      userId: memberId,
      phoneHash: `v1:attr-${id}`,
      agentId,
      source: 'ADDED_BY_AGENT',
      status: 'ACTIVE',
      windowEndsAt: at(60 * 24 * 60),
    },
  });
};

defineAgentClientContract('prisma', async () => {
  await freshTestDatabase(prisma);
  return {
    uow: new PrismaAgentUnitOfWork(prisma),
    drafts: new PrismaAgentClientDraftRepository(prisma),
    codes: new PrismaAgentClientConsentCodeStore(prisma),
    seedAgent,
    setAgentStatus: async (id: string, status: AgentStatus) => {
      await prisma.agent.update({ where: { id }, data: { status } });
    },
    seedMember,
    seedAttribution,
  };
});

describe('prisma client drafts: what only the real database shows', () => {
  const drafts = () => new PrismaAgentClientDraftRepository(prisma);
  const uow = () => new PrismaAgentUnitOfWork(prisma);
  const newDraft = (n: number, o: Record<string, unknown> = {}) => ({
    id: `draft-${n}`,
    agentId: 'agent-1',
    phoneHash: `v1:client-${n}`,
    phoneSealed: `sealed-phone-${n}`,
    phoneMasked: '+91 90***001',
    displayName: 'Priya S.',
    detailsSealed: `sealed-details-${n}`,
    expiresAt: at(14 * 24 * 60),
    createdAt: at(n),
    ...o,
  });
  const submit = (n: number) =>
    drafts().submit(
      `draft-${n}`,
      'agent-1',
      { submittedAt: at(n + 1), expiresAt: at(n + 1 + 14 * 24 * 60) },
      at(n + 1),
    );

  beforeEach(async () => {
    await freshTestDatabase(prisma);
    await seedAgent('agent-1');
  });

  it('the one-open index is reported as DUPLICATE_OPEN_CLIENT_DRAFT, even for the same phone under a new id', async () => {
    await drafts().create(newDraft(1));
    await expect(
      drafts().create(newDraft(2, { phoneHash: 'v1:client-1' })),
    ).rejects.toEqual(new AgentConflictError('DUPLICATE_OPEN_CLIENT_DRAFT'));
  });

  it('a reject waits for an accept that holds the lock, then finds the draft gone from WAITING', async () => {
    await drafts().create(newDraft(1));
    await submit(1);
    await seedMember('member-1');
    await seedAttribution('attribution-1', 'agent-1', 'member-1');

    let release!: () => void;
    const held = new Promise<void>((resolve) => (release = resolve));
    let locked!: () => void;
    const isLocked = new Promise<void>((resolve) => (locked = resolve));
    const accept = uow().run(async (tx) => {
      const row = await drafts().lockWaitingForAccept(
        'draft-1',
        ['v1:client-1'],
        at(10),
        tx,
      );
      expect(row).not.toBeNull();
      locked();
      await held;
      return drafts().markAccepted(
        'draft-1',
        {
          memberId: 'member-1',
          attributionId: 'attribution-1',
          acceptedAt: at(10),
        },
        tx,
      );
    });
    await isLocked;
    const reject = drafts().markRejected('draft-1', ['v1:client-1'], at(10));
    // The reject is blocked on the row lock until the accept commits.
    await new Promise((resolve) => setTimeout(resolve, 200));
    release();
    await expect(accept).resolves.toMatchObject({ status: 'ACCEPTED' });
    await expect(reject).resolves.toBeNull();
  });

  it("lockAgent makes a second transaction wait for the first one's commit", async () => {
    const order: string[] = [];
    let release!: () => void;
    const held = new Promise<void>((resolve) => (release = resolve));
    let locked!: () => void;
    const isLocked = new Promise<void>((resolve) => (locked = resolve));
    const first = uow().run(async (tx) => {
      await drafts().lockAgent('agent-1', tx);
      locked();
      await held;
      order.push('first done');
    });
    await isLocked;
    const second = uow().run(async (tx) => {
      await drafts().lockAgent('agent-1', tx);
      order.push('second locked');
    });
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(order).toEqual([]);
    release();
    await Promise.all([first, second]);
    expect(order).toEqual(['first done', 'second locked']);
  });

  it("deleting the member clears an accepted draft's member link and nothing else", async () => {
    await drafts().create(newDraft(1));
    await submit(1);
    await seedMember('member-1');
    await seedAttribution('attribution-1', 'agent-1', 'member-1');
    await uow().run(async (tx) => {
      await drafts().lockWaitingForAccept(
        'draft-1',
        ['v1:client-1'],
        at(10),
        tx,
      );
      await drafts().markAccepted(
        'draft-1',
        {
          memberId: 'member-1',
          attributionId: 'attribution-1',
          acceptedAt: at(10),
        },
        tx,
      );
    });
    await prisma.user.delete({ where: { id: 'member-1' } });
    expect(await drafts().findByIdForAgent('draft-1', 'agent-1')).toMatchObject(
      {
        status: 'ACCEPTED',
        memberId: null,
        attributionId: 'attribution-1',
      },
    );
  });

  it('markAccepted on a draft that is not waiting fails loudly (a bug, never a quiet success)', async () => {
    await drafts().create(newDraft(1));
    await seedMember('member-1');
    await seedAttribution('attribution-1', 'agent-1', 'member-1');
    await expect(
      uow().run((tx) =>
        drafts().markAccepted(
          'draft-1',
          {
            memberId: 'member-1',
            attributionId: 'attribution-1',
            acceptedAt: at(10),
          },
          tx,
        ),
      ),
    ).rejects.toThrow('Only a WAITING_FOR_CLIENT draft can be accepted.');
  });
});
