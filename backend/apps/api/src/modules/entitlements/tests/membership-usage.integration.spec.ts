import { ForbiddenException, Logger } from '@nestjs/common';
import type { PrismaClient, PrismaService } from '@app/database';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from '../../profiles/tests/integration-schema-guard';
import { PlanCatalogService } from '../catalog/plan-catalog.service';
import { MembershipRepository } from '../repositories/membership.repository';
import { UsageRepository } from '../repositories/usage.repository';
import { MembershipService } from '../services/membership.service';

/**
 * Concurrency, against a real Postgres. Unit tests can only show that the
 * right conditional update is issued; whether N simultaneous requests really
 * admit exactly the limit is a property of the database, so this asks one.
 * The catalogue is the one the migrations shipped into the isolated schema —
 * not a fixture — and deliberately NOT warmed first: 25 transactions against
 * a 10-connection pool with a cold catalogue is the case that once starved
 * the pool, and must not again.
 *
 * Run: INTEGRATION_DATABASE_URL=postgresql://…?schema=<throwaway> with every
 * migration applied to that schema (see docs/membership/README.md § Tests).
 */
describeIntegration('membership usage under concurrency', () => {
  jest.setTimeout(60_000);
  let prisma: PrismaClient;
  let membership: MembershipService;
  const USER = 'mbr-usage-member';
  const TARGETS = Array.from({ length: 12 }, (_, i) => `mbr-usage-target-${i}`);
  const ALL = [USER, ...TARGETS];
  const TX = { maxWait: 20_000, timeout: 20_000 };

  beforeAll(async () => {
    jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    prisma = await connectIsolatedPrisma();
    const db = prisma as unknown as PrismaService;
    membership = new MembershipService(
      db,
      new PlanCatalogService(db),
      new MembershipRepository(db),
      new UsageRepository(db),
      { membership: { enforcementMode: 'enforce' } } as never,
    );
  });

  beforeEach(async () => {
    await prisma.user.deleteMany({ where: { id: { in: ALL } } });
    for (const id of ALL) {
      await prisma.user.create({
        data: { id, firebaseUid: `fb-${id}`, email: `${id}@example.com` },
      });
    }
  });

  afterAll(async () => {
    await prisma?.user.deleteMany({ where: { id: { in: ALL } } });
    await prisma?.$disconnect();
  });

  it('admits exactly 5 of 25 simultaneous interest sends for a Free member', async () => {
    const attempts = await Promise.allSettled(
      Array.from({ length: 25 }, () =>
        prisma.$transaction(
          (tx) => membership.consume('interests.send', { userId: USER, tx }),
          TX,
        ),
      ),
    );

    const admitted = attempts.filter((a) => a.status === 'fulfilled');
    const refused = attempts.filter(
      (a): a is PromiseRejectedResult => a.status === 'rejected',
    );
    expect(admitted).toHaveLength(5);
    expect(refused).toHaveLength(20);
    for (const r of refused)
      expect(r.reason).toBeInstanceOf(ForbiddenException);

    const counter = await prisma.membershipUsageCounter.findFirst({
      where: { userId: USER, feature: 'interests.send' },
    });
    expect(counter?.used).toBe(5);
  });

  it('rolls the charge back with a transaction that fails afterwards', async () => {
    await expect(
      prisma.$transaction(async (tx) => {
        await membership.consume('interests.send', { userId: USER, tx });
        throw new Error('the interest write failed');
      }, TX),
    ).rejects.toThrow('the interest write failed');
    const counter = await prisma.membershipUsageCounter.findFirst({
      where: { userId: USER, feature: 'interests.send' },
    });
    expect(counter?.used ?? 0).toBe(0);
  });

  it('charges one per distinct profile, even when the same one is opened concurrently', async () => {
    await Promise.all(
      Array.from({ length: 10 }, () =>
        prisma.$transaction(
          (tx) =>
            membership.consume('discovery.profile_views', {
              userId: USER,
              tx,
              itemKey: 'profile-A',
            }),
          TX,
        ),
      ),
    );
    await prisma.$transaction(
      (tx) =>
        membership.consume('discovery.profile_views', {
          userId: USER,
          tx,
          itemKey: 'profile-B',
        }),
      TX,
    );
    const counter = await prisma.membershipUsageCounter.findFirst({
      where: { userId: USER, feature: 'discovery.profile_views' },
    });
    expect(counter?.used).toBe(2);
  });

  it('holds a cap under concurrent adds: a Free shortlist at 8 takes exactly 2 more', async () => {
    for (const target of TARGETS.slice(0, 8)) {
      await prisma.shortlist.create({
        data: { userId: USER, targetUserId: target },
      });
    }
    const adds = await Promise.allSettled(
      TARGETS.slice(8).map((target) =>
        prisma.$transaction(async (tx) => {
          await membership.enforceCap('shortlist.profiles', {
            userId: USER,
            tx,
            count: (db) => db.shortlist.count({ where: { userId: USER } }),
          });
          await tx.shortlist.create({
            data: { userId: USER, targetUserId: target },
          });
        }, TX),
      ),
    );
    expect(adds.filter((a) => a.status === 'fulfilled')).toHaveLength(2);
    expect(await prisma.shortlist.count({ where: { userId: USER } })).toBe(10);
  });
});
