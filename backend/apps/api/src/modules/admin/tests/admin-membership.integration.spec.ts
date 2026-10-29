import { INestApplication, Logger } from '@nestjs/common';
import request from 'supertest';
import type { App } from 'supertest/types';
import type { PrismaClient } from '@app/database';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from '../../profiles/tests/integration-schema-guard';
import { PlanCatalogAdminService } from '../../subscription/services/plan-catalog-admin.service';
import type { PlanDraftView } from '../../subscription/services/plan-draft.service';
import { SubscriptionLifecycleService } from '../../subscription/services/subscription-lifecycle.service';
import { AdminModule } from '../admin.module';
import type { AdminQueriesService } from '../services/admin-queries.service';
import {
  createAdminTestApp,
  provisionAndEnrol,
  type TestPerson,
} from './admin-test-harness';

type Result<K extends keyof AdminQueriesService> = Awaited<
  ReturnType<AdminQueriesService[K]>
>;
type PlanRow = Result<'plans'>['plans'][number];
type DraftResponse = PlanDraftView & { publishedVersion?: number | null };
type DurationInput = Pick<
  PlanRow['durations'][number],
  'months' | 'durationDays' | 'bonusDays' | 'priceInPaise' | 'isActive'
>;
type ErrorBody = { code?: string; message?: unknown };

/** A response body, typed as what the endpoint returns (dates arrive as
 *  ISO strings; `new Date(...)` accepts either). */
const json = <T>(res: { body: unknown }): T => res.body as T;

/**
 * The admin membership API over HTTP against a real Postgres: the plan
 * catalogue, drafts with maker-checker publishing, subscription lookup and
 * actions, the audit log, overview and roles. Platinum's entitlements and
 * prices are snapshotted first and restored afterwards, so other suites see
 * the catalogue they expect.
 */
describeIntegration('admin membership API over HTTP', () => {
  jest.setTimeout(90_000);
  let app: INestApplication<App>;
  let prisma: PrismaClient;
  let catalogAdmin: PlanCatalogAdminService;

  const DOMAIN = '@admin-mbr-itest.local';
  const VIEWER_ROLE = 'ITEST_PLAN_VIEWER';
  const people: Record<string, TestPerson> = {
    alice: { uid: 'adm-mbr-alice', email: `alice${DOMAIN}` },
    bob: { uid: 'adm-mbr-bob', email: `bob${DOMAIN}` },
    viewer: { uid: 'adm-mbr-viewer', email: `viewer${DOMAIN}` },
    member: { uid: 'adm-mbr-member', email: `member${DOMAIN}` },
  };
  const sessions: Record<string, string> = {};
  let aliceId: string;
  let memberSubscriptionId: string;
  let original: { entitlements: unknown; durations: DurationInput[] };

  const http = () => request(app.getHttpServer());
  const as = (who: string) => ({
    Authorization: `Bearer ${who}`,
    'X-Admin-Session': sessions[who] ?? '',
  });

  async function platinum(): Promise<PlanRow> {
    const res = await http().get('/admin/plans').set(as('alice')).expect(200);
    return json<Result<'plans'>>(res).plans.find((p) => p.code === 'PLATINUM')!;
  }

  function priceList(plan: PlanRow): DurationInput[] {
    return plan.durations.map((d) => ({
      months: d.months,
      durationDays: d.durationDays,
      bonusDays: d.bonusDays,
      priceInPaise: d.priceInPaise,
      isActive: d.isActive,
    }));
  }

  function currentEntitlements(plan: PlanRow): Record<string, unknown> {
    return {
      ...(plan.currentVersion!.entitlements as Record<string, unknown>),
    };
  }

  async function cleanup() {
    const users = await prisma.user.findMany({
      where: { email: { endsWith: DOMAIN } },
      select: { id: true },
    });
    const ids = users.map((u) => u.id);
    await prisma.subscriptionPlanDraft.deleteMany({
      where: { createdById: { in: ids } },
    });
    await prisma.auditLog.deleteMany({ where: { actorId: { in: ids } } });
    await prisma.paymentTransaction.deleteMany({
      where: { userId: { in: ids } },
    });
    await prisma.user.deleteMany({ where: { id: { in: ids } } });
    await prisma.role.deleteMany({ where: { key: VIEWER_ROLE } });
  }

  beforeAll(async () => {
    jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    prisma = await connectIsolatedPrisma();
    await cleanup();
    // Drafts left open by an interrupted earlier run would block "one open
    // draft per plan".
    await prisma.subscriptionPlanDraft.updateMany({
      where: { status: { in: ['DRAFT', 'SUBMITTED'] } },
      data: { status: 'DISCARDED' },
    });
    app = await createAdminTestApp(prisma, people, [AdminModule]);
    catalogAdmin = app.get(PlanCatalogAdminService);

    const viewer = await prisma.role.create({
      data: { key: VIEWER_ROLE, name: 'Plan viewer' },
    });
    const planView = await prisma.permission.findUniqueOrThrow({
      where: { key: 'plan.view' },
    });
    await prisma.rolePermission.create({
      data: { roleId: viewer.id, permissionId: planView.id },
    });
    for (const [who, role] of [
      ['alice', 'SUPER_ADMIN'],
      ['bob', 'SUPER_ADMIN'],
      ['viewer', VIEWER_ROLE],
    ] as const) {
      ({ session: sessions[who] } = await provisionAndEnrol(
        app,
        prisma,
        who,
        people[who],
        role,
      ));
    }
    aliceId = (
      await prisma.user.findUniqueOrThrow({
        where: { email: people.alice.email },
      })
    ).id;

    const p = await platinum();
    original = {
      entitlements: currentEntitlements(p),
      durations: priceList(p),
    };

    const member = await prisma.user.create({
      data: {
        firebaseUid: people.member.uid,
        email: people.member.email,
        phone: '+919812345210',
        status: 'ACTIVE',
      },
    });
    ({ subscriptionId: memberSubscriptionId } = await app
      .get(SubscriptionLifecycleService)
      .grant({
        userId: member.id,
        planCode: 'GOLD',
        days: 30,
        actorId: aliceId,
        reason: 'integration fixture',
      }));
  });

  afterAll(async () => {
    if (app && original) {
      await catalogAdmin.publishVersion({
        planCode: 'PLATINUM',
        entitlements: original.entitlements,
        changeNote: 'integration test: restore',
        actorId: aliceId,
      });
      for (const d of original.durations) {
        await catalogAdmin.setDuration({
          planCode: 'PLATINUM',
          ...d,
          actorId: aliceId,
          reason: 'integration test: restore',
        });
      }
    }
    await app?.close();
    if (prisma) await cleanup();
    await prisma?.$disconnect();
  });

  describe('plan catalogue', () => {
    it('lists every plan with its current version, prices and the feature registry', async () => {
      const res = await http()
        .get('/admin/plans')
        .set(as('viewer'))
        .expect(200);
      const catalogue = json<Result<'plans'>>(res);
      expect(catalogue.plans.map((p) => p.code)).toEqual(
        expect.arrayContaining(['FREE', 'GOLD', 'PLATINUM']),
      );
      expect(catalogue.features.length).toBeGreaterThan(40);
    });

    it('needs plan.edit to change display text, and a reason', async () => {
      await http()
        .patch('/admin/plans/PLATINUM/display')
        .set(as('viewer'))
        .send({ description: 'x', reason: 'try' })
        .expect(403);
      await http()
        .patch('/admin/plans/PLATINUM/display')
        .set(as('alice'))
        .send({ description: 'Everything in Gold, and more.' })
        .expect(400);
      await http()
        .patch('/admin/plans/NOPE/display')
        .set(as('alice'))
        .send({ description: 'x', reason: 'bad plan' })
        .expect(400);
    });
  });

  describe('drafts: maker-checker publishing', () => {
    let draftId: string;
    const price = 900_000 + Math.floor(Math.random() * 90_000);

    it('starts from the plan as it is, one open draft per plan', async () => {
      const res = await http()
        .post('/admin/plan-drafts')
        .set(as('alice'))
        .send({ planCode: 'PLATINUM', changeNote: 'New 3-month price' })
        .expect(201);
      const draft = json<DraftResponse>(res);
      draftId = draft.id;
      expect(draft).toMatchObject({
        status: 'DRAFT',
        planCode: 'PLATINUM',
        stale: false,
        review: { hasChanges: false, publishable: false },
      });
      await http()
        .post('/admin/plan-drafts')
        .set(as('bob'))
        .send({ planCode: 'PLATINUM', changeNote: 'Another one' })
        .expect(409);
      await http()
        .post('/admin/plan-drafts')
        .set(as('viewer'))
        .send({ planCode: 'GOLD', changeNote: 'Viewer cannot' })
        .expect(403);
    });

    it('validates edits and explains what blocks publishing', async () => {
      const durations = priceList(await platinum());
      const withThree = (over: Partial<DurationInput>) =>
        durations.map((d) => (d.months === 3 ? { ...d, ...over } : d));

      const invalid = json<DraftResponse>(
        await http()
          .put(`/admin/plan-drafts/${draftId}`)
          .set(as('alice'))
          .send({
            durations: withThree({ priceInPaise: null, isActive: true }),
          })
          .expect(200),
      );
      expect(invalid.review.publishable).toBe(false);
      expect(invalid.review.durationProblems.join(' ')).toContain(
        'must be priced',
      );

      const valid = json<DraftResponse>(
        await http()
          .put(`/admin/plan-drafts/${draftId}`)
          .set(as('alice'))
          .send({
            durations: withThree({ priceInPaise: price, isActive: true }),
          })
          .expect(200),
      );
      expect(valid.review).toMatchObject({
        publishable: true,
        changedFeatures: [],
        durationProblems: [],
      });
      expect(valid.review.durationChanges[0].after.priceInPaise).toBe(price);
    });

    it('the submitter cannot publish their own draft; a second admin can', async () => {
      await http()
        .post(`/admin/plan-drafts/${draftId}/submit`)
        .set(as('alice'))
        .expect(200);
      await http()
        .put(`/admin/plan-drafts/${draftId}`)
        .set(as('alice'))
        .send({ changeNote: 'too late' })
        .expect(409);

      const own = await http()
        .post(`/admin/plan-drafts/${draftId}/publish`)
        .set(as('alice'))
        .send({})
        .expect(403);
      expect(json<ErrorBody>(own).code).toBe('PLAN_DRAFT_NEEDS_SECOND_ADMIN');
      await http()
        .post(`/admin/plan-drafts/${draftId}/publish`)
        .set(as('viewer'))
        .send({})
        .expect(403);

      const published = json<DraftResponse>(
        await http()
          .post(`/admin/plan-drafts/${draftId}/publish`)
          .set(as('bob'))
          .send({ note: 'Checked with Raja' })
          .expect(200),
      );
      expect(published).toMatchObject({
        status: 'PUBLISHED',
        publishedVersion: null, // prices only: no new entitlement version
      });
      const three = (await platinum()).durations.find((d) => d.months === 3);
      expect(three).toMatchObject({ priceInPaise: price, isActive: true });

      const audit = json<Result<'auditLogs'>>(
        await http()
          .get('/admin/audit-logs')
          .query({ entityId: draftId })
          .set(as('alice'))
          .expect(200),
      );
      expect(audit.items.map((r) => r.action)).toEqual(
        expect.arrayContaining([
          'membership.plan.draft.create',
          'membership.plan.draft.submit',
          'membership.plan.draft.publish',
        ]),
      );
    });

    it('publishes an entitlement change as a new version', async () => {
      const p = await platinum();
      const created = json<DraftResponse>(
        await http()
          .post('/admin/plan-drafts')
          .set(as('bob'))
          .send({ planCode: 'PLATINUM', changeNote: 'Toggle a feature' })
          .expect(201),
      );
      const entitlements = currentEntitlements(p);
      const key = Object.keys(entitlements).find(
        (k) =>
          typeof entitlements[k] === 'boolean' && k !== 'search.verified_only',
      )!;
      entitlements[key] = !entitlements[key];
      await http()
        .put(`/admin/plan-drafts/${created.id}`)
        .set(as('bob'))
        .send({ entitlements })
        .expect(200);
      await http()
        .post(`/admin/plan-drafts/${created.id}/submit`)
        .set(as('bob'))
        .expect(200);
      const published = json<DraftResponse>(
        await http()
          .post(`/admin/plan-drafts/${created.id}/publish`)
          .set(as('alice'))
          .send({})
          .expect(200),
      );
      expect(published.publishedVersion).toBe(p.currentVersion!.version + 1);
      expect(currentEntitlements(await platinum())[key]).toBe(
        entitlements[key],
      );
    });

    it('a second admin can reject with a reason; the submitter cannot', async () => {
      const created = json<DraftResponse>(
        await http()
          .post('/admin/plan-drafts')
          .set(as('alice'))
          .send({ planCode: 'PLATINUM', changeNote: 'Will be rejected' })
          .expect(201),
      );
      await http()
        .put(`/admin/plan-drafts/${created.id}`)
        .set(as('alice'))
        .send({
          durations: priceList(await platinum()).map((d) => ({
            ...d,
            bonusDays: d.bonusDays + 7,
          })),
        })
        .expect(200);
      await http()
        .post(`/admin/plan-drafts/${created.id}/submit`)
        .set(as('alice'))
        .expect(200);
      await http()
        .post(`/admin/plan-drafts/${created.id}/reject`)
        .set(as('alice'))
        .send({ reason: 'self reject' })
        .expect(403);
      const rejected = json<DraftResponse>(
        await http()
          .post(`/admin/plan-drafts/${created.id}/reject`)
          .set(as('bob'))
          .send({ reason: 'Bonus days not agreed yet' })
          .expect(200),
      );
      expect(rejected).toMatchObject({
        status: 'REJECTED',
        decisionNote: 'Bonus days not agreed yet',
      });
    });

    it('refuses a draft the plan has moved past (stale), which can then be discarded', async () => {
      const created = json<DraftResponse>(
        await http()
          .post('/admin/plan-drafts')
          .set(as('alice'))
          .send({ planCode: 'PLATINUM', changeNote: 'Will go stale' })
          .expect(201),
      );
      await catalogAdmin.publishVersion({
        planCode: 'PLATINUM',
        entitlements: currentEntitlements(await platinum()),
        changeNote: 'Published elsewhere meanwhile',
        actorId: aliceId,
      });
      const stale = json<DraftResponse>(
        await http()
          .get(`/admin/plan-drafts/${created.id}`)
          .set(as('viewer'))
          .expect(200),
      );
      expect(stale).toMatchObject({
        stale: true,
        review: { publishable: false },
      });
      await http()
        .post(`/admin/plan-drafts/${created.id}/submit`)
        .set(as('alice'))
        .expect(409);
      const discarded = json<DraftResponse>(
        await http()
          .post(`/admin/plan-drafts/${created.id}/discard`)
          .set(as('alice'))
          .send({ reason: 'Plan changed underneath' })
          .expect(200),
      );
      expect(discarded.status).toBe('DISCARDED');
    });
  });

  describe('subscriptions', () => {
    it('finds a member by exact email, with contact details masked', async () => {
      const page = json<Result<'subscriptions'>>(
        await http()
          .get('/admin/subscriptions')
          .query({ q: people.member.email })
          .set(as('alice'))
          .expect(200),
      );
      const [row] = page.items;
      expect(row).toMatchObject({
        id: memberSubscriptionId,
        status: 'ACTIVE',
        source: 'ADMIN_GRANT',
        plan: { code: 'GOLD' },
      });
      expect(row.member.email).not.toBe(people.member.email);
      expect(row.member.email).toMatch(/^me\*+@/);
      expect(row.member.phone).toBe('+91 98***210');

      await http()
        .get('/admin/subscriptions')
        .query({ q: 'mem' })
        .set(as('alice'))
        .expect(400);
      await http().get('/admin/subscriptions').set(as('viewer')).expect(403);
    });

    it('extends by at most 30 days with a reason, then revokes', async () => {
      const url = `/admin/subscriptions/${memberSubscriptionId}`;
      const before = json<Result<'subscription'>>(
        await http().get(url).set(as('alice')).expect(200),
      );
      await http()
        .post(`${url}/extend`)
        .set(as('alice'))
        .send({ days: 31, reason: 'too long' })
        .expect(400);
      await http()
        .post(`${url}/extend`)
        .set(as('alice'))
        .send({ days: 7 })
        .expect(400);
      const extended = json<Result<'subscription'>>(
        await http()
          .post(`${url}/extend`)
          .set(as('alice'))
          .send({ days: 7, reason: 'Outage compensation' })
          .expect(200),
      );
      expect(
        new Date(extended.endDate).getTime() -
          new Date(before.endDate).getTime(),
      ).toBe(7 * 24 * 3600 * 1000);

      const revoked = json<Result<'subscription'>>(
        await http()
          .post(`${url}/revoke`)
          .set(as('alice'))
          .send({ reason: 'Fraudulent account' })
          .expect(200),
      );
      expect(revoked.status).toBe('CANCELLED');
      expect(revoked.events.map((e) => e.type)).toEqual([
        'GRANTED',
        'EXTENDED',
        'REVOKED',
      ]);
    });
  });

  describe('audit log, overview and roles', () => {
    it('audit log needs audit.view and is newest-first with a cursor', async () => {
      await http().get('/admin/audit-logs').set(as('viewer')).expect(403);
      const first = json<Result<'auditLogs'>>(
        await http()
          .get('/admin/audit-logs')
          .query({ actorId: aliceId, limit: 2 })
          .set(as('alice'))
          .expect(200),
      );
      expect(first.items).toHaveLength(2);
      expect(first.items[0].actor).toBe(people.alice.email);
      expect(first.nextCursor).toEqual(expect.any(String));
      const second = json<Result<'auditLogs'>>(
        await http()
          .get('/admin/audit-logs')
          .query({ actorId: aliceId, limit: 2, cursor: first.nextCursor })
          .set(as('alice'))
          .expect(200),
      );
      expect(new Date(second.items[0].createdAt).getTime()).toBeLessThanOrEqual(
        new Date(first.items[1].createdAt).getTime(),
      );
    });

    it('overview shows real counts, and revenue only with finance.view', async () => {
      const overview = json<Result<'overview'>>(
        await http().get('/admin/overview').set(as('alice')).expect(200),
      );
      expect(overview.members.total).toBeGreaterThan(0);
      // Alice holds finance.view (Super Admin), so revenue is included.
      expect(typeof overview.revenueLast30Days?.grossInPaise).toBe('number');
      await http().get('/admin/overview').set(as('viewer')).expect(403);
    });

    it('roles list (rbac.manage) names each role’s admins', async () => {
      const roles = json<Result<'roles'>>(
        await http().get('/admin/roles').set(as('bob')).expect(200),
      );
      const sa = roles.roles.find((r) => r.key === 'SUPER_ADMIN')!;
      expect(sa.permissions).toHaveLength(48);
      expect(sa.admins.map((a) => a.email)).toEqual(
        expect.arrayContaining([people.alice.email, people.bob.email]),
      );
      // Raja's roles (28 Oct): exactly these keys, nothing more.
      const grants = (key: string) =>
        roles.roles.find((r) => r.key === key)?.permissions;
      expect(grants('PARTNER_MANAGER')).toEqual([
        'agent.approve',
        'agent.view',
      ]);
      expect(grants('PAYOUT_MANAGER')).toEqual([
        'payout.execute',
        'payout.view',
      ]);
      await http().get('/admin/roles').set(as('viewer')).expect(403);
    });
  });
});
