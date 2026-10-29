/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md): the
 * attribution repository, applicant store and attempt store against a
 * throwaway LOCAL Postgres. Runs the SAME contract suite as the in-memory
 * fakes, then what only the real adapters do: delete rules, and the bounded
 * purge of expired rows.
 */
import type { AgentClock } from '../../ports/agent-infra-ports';
import { defineAgentStoresContract } from '../../testing/agent-stores.contract';
import { PrismaAgentApplicantRepository } from './prisma-agent-applicant.repository';
import { PrismaAgentRepository } from './prisma-agent.repository';
import { PrismaReferralAttributionRepository } from './prisma-referral-attribution.repository';
import { PrismaReferralCodeAttemptStore } from './prisma-referral-code-attempt.store';
import { PrismaReferralCodeRepository } from './prisma-referral-code.repository';
import { openTestDatabase, truncateAgentTables } from './prisma-test-database';

const db = openTestDatabase();
const prisma = db.prisma;

afterAll(async () => {
  await truncateAgentTables(prisma);
  await db.close();
});

const NOW = new Date('2026-10-29T09:00:00.000Z');
const DAY = 86_400_000;
const clock: AgentClock = { now: () => NOW };

const seedUser = (id: string) =>
  prisma.user.upsert({
    where: { id },
    create: { id, firebaseUid: `fb-${id}`, email: `${id}@example.invalid` },
    update: {},
  });

/** A purge that never reaches the contract data: a year of grace. */
const contractPurge = { batchSize: 10, graceMs: 365 * DAY, clock };

defineAgentStoresContract('prisma', async () => {
  await truncateAgentTables(prisma);
  return {
    agents: new PrismaAgentRepository(prisma),
    codes: new PrismaReferralCodeRepository(prisma),
    attributions: new PrismaReferralAttributionRepository(prisma),
    applicants: new PrismaAgentApplicantRepository(prisma, contractPurge),
    attempts: new PrismaReferralCodeAttemptStore(prisma, contractPurge),
    seedMember: async (id) => {
      await seedUser(id);
    },
    cleanup: () => truncateAgentTables(prisma),
  };
});

describe('prisma attribution repository: delete rules', () => {
  beforeEach(() => truncateAgentTables(prisma));

  async function seedAttribution() {
    const agents = new PrismaAgentRepository(prisma);
    const codes = new PrismaReferralCodeRepository(prisma);
    const attributions = new PrismaReferralAttributionRepository(prisma);
    await agents.create({
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
    await codes.create({
      id: 'code-1',
      agentId: 'agent-1',
      code: 'NM7K2P9X',
      isPrimary: true,
      isActive: true,
      createdAt: NOW,
    });
    await seedUser('member-1');
    await attributions.create({
      id: 'attr-1',
      memberId: 'member-1',
      agentId: 'agent-1',
      codeId: 'code-1',
      source: 'CODE_AT_SIGNUP',
      memberPhoneHash: 'v1:member-hash-1',
      attributedAt: NOW,
      status: 'ACTIVE',
      windowEndsAt: new Date(NOW.getTime() + 60 * DAY),
      needsReview: false,
    });
    return attributions;
  }

  it('deleting the member keeps the attribution with a null member', async () => {
    const attributions = await seedAttribution();
    await prisma.user.delete({ where: { id: 'member-1' } });
    expect(await attributions.findByMemberId('member-1')).toBeNull();
    const rows = await attributions.listByAgent('agent-1');
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ memberId: null, codeId: 'code-1' });
  });

  it('deleting the code keeps the attribution with a null code', async () => {
    const attributions = await seedAttribution();
    await prisma.referralCode.delete({ where: { id: 'code-1' } });
    expect((await attributions.listByAgent('agent-1'))[0]).toMatchObject({
      memberId: 'member-1',
      codeId: null,
    });
  });

  it('an agent with attributions cannot be deleted (history is kept)', async () => {
    await seedAttribution();
    await expect(
      prisma.agent.delete({ where: { id: 'agent-1' } }),
    ).rejects.toThrow();
  });
});

describe('prisma applicant store: bounded purge on write', () => {
  const GRACE = 1 * DAY;
  const cutoff = new Date(NOW.getTime() - GRACE);
  const row = (hash: string, expiresAt: Date) => ({
    phoneHash: hash,
    phoneSealed: 'v1:sealed',
    expiresAt,
  });

  beforeEach(() => truncateAgentTables(prisma));

  const store = (batchSize: number, logger?: { warn(m: string): void }) =>
    new PrismaAgentApplicantRepository(prisma, {
      batchSize,
      graceMs: GRACE,
      clock,
      logger,
    });
  const hashes = async () =>
    (await prisma.agentApplicant.findMany({ select: { phoneHash: true } }))
      .map((r) => r.phoneHash)
      .sort();

  it('removes rows expired before the cutoff, keeps the boundary and live rows', async () => {
    const repo = store(10);
    for (const r of [
      row('old', new Date(cutoff.getTime() - 1)),
      row('at-cutoff', cutoff),
      row('just-expired', new Date(NOW.getTime() - 1)),
      row('live', new Date(NOW.getTime() + DAY)),
    ]) {
      await prisma.agentApplicant.create({ data: r });
    }
    await repo.save(row('new', new Date(NOW.getTime() + DAY)));
    // Only the row strictly before `now - grace` is purged.
    expect(await hashes()).toEqual(
      ['at-cutoff', 'just-expired', 'live', 'new'].sort(),
    );
  });

  it('purges at most batchSize rows per write, oldest first', async () => {
    const repo = store(2);
    for (let i = 1; i <= 5; i++) {
      await prisma.agentApplicant.create({
        data: row(`old-${i}`, new Date(cutoff.getTime() - (10 - i) * DAY)),
      });
    }
    await repo.save(row('new', new Date(NOW.getTime() + DAY)));
    // old-1 and old-2 expired longest ago, so they go first.
    expect(await hashes()).toEqual(['new', 'old-3', 'old-4', 'old-5']);
    await repo.save(row('new-2', new Date(NOW.getTime() + DAY)));
    expect(await hashes()).toEqual(['new', 'new-2', 'old-5']);
  });

  it('never purges the row this write just stored, even if it is already expired', async () => {
    const repo = store(10);
    await repo.save(row('stale', new Date(cutoff.getTime() - 365 * DAY)));
    expect(await hashes()).toEqual(['stale']);
    // A later write for another hash does purge it.
    await repo.save(row('next', new Date(NOW.getTime() + DAY)));
    expect(await hashes()).toEqual(['next']);
  });

  it('a purge failure never fails the write and logs no values', async () => {
    const warnings: string[] = [];
    const failing = new Proxy(prisma, {
      get(target, prop, receiver) {
        if (prop === 'agentApplicant') {
          return new Proxy(target.agentApplicant, {
            get(t, p, r) {
              if (p === 'findMany') {
                return () =>
                  Promise.reject(new Error('SECRET phone +919000000001'));
              }
              return Reflect.get(t, p, r) as unknown;
            },
          });
        }
        return Reflect.get(target, prop, receiver) as unknown;
      },
    });
    const repo = new PrismaAgentApplicantRepository(failing, {
      batchSize: 5,
      graceMs: GRACE,
      clock,
      logger: { warn: (m) => warnings.push(m) },
    });
    await expect(
      repo.save(row('kept', new Date(NOW.getTime() + DAY))),
    ).resolves.toBeUndefined();
    expect(await hashes()).toEqual(['kept']);
    expect(warnings).toHaveLength(1);
    expect(warnings[0]).not.toMatch(/SECRET|919000000001|kept/);
  });

  it('refuses a bad batch size or grace at construction', () => {
    for (const bad of [0, -1, 1.5, Number.NaN]) {
      expect(() => store(bad)).toThrow(RangeError);
    }
    expect(
      () =>
        new PrismaAgentApplicantRepository(prisma, {
          batchSize: 1,
          graceMs: -1,
          clock,
        }),
    ).toThrow(RangeError);
  });
});

describe('prisma attempt store: bounded purge on write', () => {
  const GRACE = 1 * DAY;
  const cutoff = new Date(NOW.getTime() - GRACE);

  beforeEach(() => truncateAgentTables(prisma));

  const store = (batchSize: number) =>
    new PrismaReferralCodeAttemptStore(prisma, {
      batchSize,
      graceMs: GRACE,
      clock,
    });
  const times = async () =>
    (
      await prisma.referralCodeAttempt.findMany({
        select: { attemptedAt: true },
      })
    )
      .map((r) => r.attemptedAt.getTime())
      .sort((a, b) => a - b);

  it('removes attempts older than the cutoff, keeps the boundary and newer ones', async () => {
    for (const t of [
      cutoff.getTime() - 1,
      cutoff.getTime(),
      NOW.getTime() - 1000,
    ]) {
      await prisma.referralCodeAttempt.create({
        data: { requesterKey: 'r', codeKey: null, attemptedAt: new Date(t) },
      });
    }
    await store(10).record({ requesterKey: 'r', codeKey: null, at: NOW });
    expect(await times()).toEqual([
      cutoff.getTime(),
      NOW.getTime() - 1000,
      NOW.getTime(),
    ]);
  });

  it('purges at most batchSize attempts per write, oldest first', async () => {
    for (let i = 1; i <= 5; i++) {
      await prisma.referralCodeAttempt.create({
        data: {
          requesterKey: 'r',
          codeKey: null,
          attemptedAt: new Date(cutoff.getTime() - (10 - i) * DAY),
        },
      });
    }
    await store(2).record({ requesterKey: 'r', codeKey: null, at: NOW });
    const left = await times();
    expect(left).toHaveLength(4); // 5 old + 1 new - 2 purged
    expect(left[0]).toBe(cutoff.getTime() - 7 * DAY); // the two oldest are gone
  });

  it('does not purge when the write is refused (raw IP)', async () => {
    await prisma.referralCodeAttempt.create({
      data: {
        requesterKey: 'r',
        codeKey: null,
        attemptedAt: new Date(cutoff.getTime() - DAY),
      },
    });
    await expect(
      store(10).record({ requesterKey: '203.0.113.7', codeKey: null, at: NOW }),
    ).rejects.toThrow(RangeError);
    expect(await times()).toHaveLength(1);
  });

  it('refuses a bad batch size at construction', () => {
    expect(() => store(0)).toThrow(RangeError);
  });
});
