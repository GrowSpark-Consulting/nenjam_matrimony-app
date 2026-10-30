import {
  type CanActivate,
  type ExecutionContext,
  Global,
  Injectable,
  type INestApplication,
  Module,
  UnauthorizedException,
} from '@nestjs/common';
import { DiscoveryModule, Reflector } from '@nestjs/core';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import type { App } from 'supertest/types';
import { ApiValidationPipe, FirebaseAuthGuard } from '@app/common';
import { PrismaService } from '@app/database';
import { AdminModule } from '../../admin/admin.module';
import { AdminGuard } from '../../admin/auth/admin.guard';
import type { AdminRequest } from '../../admin/auth/admin-request';
import { adminForbidden } from '../../admin/auth/admin-auth.policy';
import {
  ADMIN_ROUTE_POLICY,
  type AdminRoutePolicy,
} from '../../admin/auth/admin-route-policy';
import { AdminRouteCheck } from '../../admin/auth/admin-route-check';
import { AdminAuditService } from '../../admin/services/admin-audit.service';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { DailyJobRegistry } from '../../platform/jobs/daily-job.registry';
import { PlatformModule } from '../../platform/platform.module';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import { ReferralEventBus } from '../../subscription/events/referral-event-bus';
import { SubscriptionModule } from '../../subscription/subscription.module';
import { AgentsModule } from '../agents.module';
import { AgentPaymentEventsSubscriber } from '../commission/agent-payment-events.subscriber';
import { makeAdminHarness, PAYER, SUPER } from '../testing/agent-admin-harness';
import { makeAgentAdminHarness } from '../testing/agent-admin-agents-harness';
import { AgentAdminAgentsService } from './agent-admin-agents.service';
import { AgentAdminRestDeps } from './agent-admin-rest.wiring';

const UUID = (n: number) =>
  `22222222-2222-4222-8222-${String(n).padStart(12, '0')}`;

/** Door permissions come from a header so each test names exactly what the
 *  caller holds; step-up from another. */
@Injectable()
class StandInAdminGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(ctx: ExecutionContext): boolean {
    const req = ctx.switchToHttp().getRequest<AdminRequest>();
    const userId = req.headers['x-test-admin'];
    if (typeof userId !== 'string') throw new UnauthorizedException();
    const held = String(req.headers['x-test-perms'] ?? '')
      .split(',')
      .filter(Boolean);
    const policy = this.reflector.get<AdminRoutePolicy | undefined>(
      ADMIN_ROUTE_POLICY,
      ctx.getHandler(),
    );
    const missing = (policy?.permissions ?? []).filter(
      (p) => !held.includes(p),
    );
    if (missing.length > 0) {
      throw adminForbidden(
        'ADMIN_PERMISSION_DENIED',
        `Not permitted: requires ${missing.join(', ')}.`,
        { missing },
      );
    }
    req.admin = {
      adminAccountId: `acct-${userId}`,
      userId,
      email: `${userId}@example.invalid`,
      department: 'ops',
      lastLoginAt: null,
      sessionId: 'session-1',
      stepUpVerifiedAt: req.headers['x-test-stepup'] ? new Date() : null,
      roles: [],
      permissions: held as never,
    };
    return true;
  }
}

@Global()
@Module({
  providers: [{ provide: PrismaService, useValue: {} }],
  exports: [PrismaService],
})
class StandInDatabaseModule {}

@Module({
  imports: [DiscoveryModule],
  providers: [
    { provide: AdminAuditService, useValue: { record: jest.fn() } },
    { provide: AdminGuard, useClass: StandInAdminGuard },
    AdminRouteCheck,
  ],
  exports: [AdminAuditService, AdminGuard],
})
class StandInAdminModule {}

@Module({
  providers: [
    {
      provide: IdentifierHashService,
      useValue: {
        available: false,
        hashIdentifier: jest.fn(),
        hashIdentifierAll: jest.fn(),
      },
    },
    {
      provide: PlatformSettingsService,
      useValue: {
        getMany: jest.fn().mockResolvedValue({}),
        registerValidator: jest.fn(),
      },
    },
    DailyJobRegistry,
  ],
  exports: [IdentifierHashService, PlatformSettingsService, DailyJobRegistry],
})
class StandInPlatformModule {}

@Module({ providers: [ReferralEventBus], exports: [ReferralEventBus] })
class StandInSubscriptionModule {}

async function boot(rest: AgentAdminRestDeps, agents: AgentAdminAgentsService) {
  const moduleRef = await Test.createTestingModule({
    imports: [StandInDatabaseModule, AgentsModule],
  })
    .overrideModule(AdminModule)
    .useModule(StandInAdminModule)
    .overrideModule(PlatformModule)
    .useModule(StandInPlatformModule)
    .overrideModule(SubscriptionModule)
    .useModule(StandInSubscriptionModule)
    .overrideGuard(FirebaseAuthGuard)
    .useValue({ canActivate: () => true })
    .overrideGuard(AdminGuard)
    .useClass(StandInAdminGuard)
    .overrideProvider(AgentAdminRestDeps)
    .useValue(rest)
    .overrideProvider(AgentAdminAgentsService)
    .useValue(agents)
    .overrideProvider(AgentPaymentEventsSubscriber)
    .useValue({ onModuleInit: () => undefined })
    .compile();
  const app = moduleRef.createNestApplication<INestApplication<App>>();
  app.useGlobalPipes(
    new ApiValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );
  await app.init();
  return app;
}

function adminWorld() {
  const h = makeAdminHarness();
  const a = makeAgentAdminHarness();
  // PR A's service checks agent.manage again inside its transaction.
  a.permission.grant(SUPER, { module: 'agent', action: 'manage' });
  const rest = new AgentAdminRestDeps(
    h.agentsAdmin,
    h.referralsAdmin,
    h.commissionsAdmin,
    h.payoutsAdmin,
  );
  return { h, a, rest };
}

const REASON = { reason: 'Checked by the test.' };

/** Every new route with the exact permission the contract names. */
const ROUTES: Array<
  [method: 'get' | 'post', path: string, key: string, body: object | null]
> = [
  ['post', `/admin/agents/${UUID(1)}/pause`, 'agent.manage', REASON],
  ['post', `/admin/agents/${UUID(1)}/resume`, 'agent.manage', REASON],
  ['post', `/admin/agents/${UUID(1)}/terminate`, 'agent.manage', REASON],
  ['post', `/admin/agents/${UUID(1)}/codes/replace`, 'agent.manage', REASON],
  [
    'post',
    `/admin/agents/${UUID(1)}/payout-details/verify`,
    'agent.payout_details.verify',
    REASON,
  ],
  [
    'post',
    `/admin/agents/${UUID(1)}/pan/verify`,
    'agent.payout_details.verify',
    REASON,
  ],
  [
    'post',
    `/admin/agents/${UUID(1)}/reveal`,
    'agent.pii.reveal',
    { fields: ['PAN'], ...REASON },
  ],
  ['get', `/admin/agents/${UUID(1)}/referrals`, 'attribution.view', null],
  [
    'post',
    `/admin/referrals/${UUID(1)}/correct`,
    'attribution.override',
    { action: 'CLEAR_REVIEW', ...REASON },
  ],
  ['get', '/admin/commissions', 'commission.view', null],
  [
    'post',
    `/admin/commissions/${UUID(1)}/approve`,
    'commission.approve',
    REASON,
  ],
  ['post', `/admin/commissions/${UUID(1)}/cancel`, 'commission.cancel', REASON],
  [
    'post',
    `/admin/commissions/${UUID(1)}/override`,
    'commission.override',
    { amountPaise: 100, ...REASON },
  ],
  ['get', '/admin/payouts', 'payout.view', null],
  [
    'post',
    '/admin/payouts',
    'payout.execute',
    { agentId: UUID(1), period: '2026-11', ...REASON },
  ],
  ['get', `/admin/payouts/${UUID(1)}`, 'payout.view', null],
  [
    'post',
    `/admin/payouts/${UUID(1)}/mark-paid`,
    'payout.execute',
    { reference: 'UTR123', paidAt: '2026-11-05T10:00:00.000Z', ...REASON },
  ],
  ['post', `/admin/payouts/${UUID(1)}/cancel`, 'payout.execute', REASON],
];

describe('remaining admin agent-program routes over HTTP', () => {
  let app: INestApplication<App>;
  afterEach(() => app?.close());

  it.each(ROUTES)('%s %s needs exactly %s', async (method, path, key, body) => {
    const w = adminWorld();
    app = await boot(w.rest, w.a.service);
    const others = ROUTES.map((r) => r[2]).filter((k) => k !== key);
    const without = await request(app.getHttpServer())
      [method](path)
      .set({
        'x-test-admin': SUPER,
        'x-test-perms': [...new Set(others)].join(','),
      })
      .send(body ?? undefined);
    expect(without.status).toBe(403);
    expect(without.body).toMatchObject({
      code: 'ADMIN_PERMISSION_DENIED',
      missing: [key],
    });
    const withKey = await request(app.getHttpServer())
      [method](path)
      .set({ 'x-test-admin': SUPER, 'x-test-perms': key, 'x-test-stepup': '1' })
      .send(body ?? undefined);
    expect(withKey.status).not.toBe(403);
    expect(withKey.status).toBeLessThan(500);
  });

  it('a non-uuid id is 400 VALIDATION_FAILED', async () => {
    const w = adminWorld();
    app = await boot(w.rest, w.a.service);
    const res = await request(app.getHttpServer())
      .post('/admin/commissions/not-a-uuid/approve')
      .set({ 'x-test-admin': SUPER, 'x-test-perms': 'commission.approve' })
      .send(REASON);
    expect(res.status).toBe(400);
    expect(res.body).toMatchObject({ code: 'VALIDATION_FAILED' });
  });

  it('bad bodies are 400: short reason, REASSIGN without agentId, bad period, negative override', async () => {
    const w = adminWorld();
    app = await boot(w.rest, w.a.service);
    const as = {
      'x-test-admin': SUPER,
      'x-test-perms': ROUTES.map((r) => r[2]).join(','),
      'x-test-stepup': '1',
    };
    for (const [path, body] of [
      [`/admin/agents/${UUID(1)}/pause`, { reason: 'x' }],
      [
        `/admin/referrals/${UUID(1)}/correct`,
        { action: 'REASSIGN_AGENT', ...REASON },
      ],
      ['/admin/payouts', { agentId: UUID(1), period: '2026-13', ...REASON }],
      [
        `/admin/commissions/${UUID(1)}/override`,
        { amountPaise: -1, ...REASON },
      ],
    ] as const) {
      const res = await request(app.getHttpServer())
        .post(path)
        .set(as)
        .send(body);
      expect([path, res.status]).toEqual([path, 400]);
    }
  });

  it('pause, resume and terminate follow the state machine and audit with the request context', async () => {
    const w = adminWorld();
    const agent = await w.a.seedAgent(1, 'ACTIVE');
    w.a.permission.grant(SUPER, { module: 'agent', action: 'manage' });
    app = await boot(w.rest, w.a.service);
    const as = { 'x-test-admin': SUPER, 'x-test-perms': 'agent.manage' };
    const go = (action: string) =>
      request(app.getHttpServer())
        .post(`/admin/agents/${agent.id}/${action}`)
        .set(as)
        .send(REASON);
    expect((await go('pause')).body).toMatchObject({ status: 'SUSPENDED' });
    const again = await go('pause');
    expect(again.status).toBe(409);
    expect(again.body).toMatchObject({
      code: 'AGENT_TRANSITION_NOT_ALLOWED',
      agentStatus: 'SUSPENDED',
    });
    expect((await go('resume')).body).toMatchObject({ status: 'ACTIVE' });
    expect((await go('terminate')).body).toMatchObject({
      status: 'TERMINATED',
    });
    const after = await go('resume');
    expect(after.status).toBe(409);
    expect(after.body).toMatchObject({ refusal: 'TERMINATED_IS_FINAL' });
    const actions = w.a.audit.entries.map((e) => e.action);
    expect(actions).toEqual(['agent.pause', 'agent.resume', 'agent.terminate']);
    for (const e of w.a.audit.entries) {
      expect(e.context?.requestId).toEqual(expect.any(String));
    }
  });

  it('pause from PENDING_APPROVAL is refused (approve is not resume)', async () => {
    const w = adminWorld();
    const agent = await w.a.seedAgent(1, 'PENDING_APPROVAL');
    w.a.permission.grant(SUPER, { module: 'agent', action: 'manage' });
    app = await boot(w.rest, w.a.service);
    const res = await request(app.getHttpServer())
      .post(`/admin/agents/${agent.id}/resume`)
      .set({ 'x-test-admin': SUPER, 'x-test-perms': 'agent.manage' })
      .send(REASON);
    expect(res.status).toBe(409);
  });

  it('reveal without a fresh step-up is 401 ADMIN_STEP_UP_REQUIRED; with it the PAN once', async () => {
    const w = adminWorld();
    await w.h.seedApplicant(UUID(7));
    app = await boot(w.rest, w.a.service);
    const send = (stepUp: boolean) =>
      request(app.getHttpServer())
        .post(`/admin/agents/${UUID(7)}/reveal`)
        .set({
          'x-test-admin': SUPER,
          'x-test-perms': 'agent.pii.reveal',
          ...(stepUp && { 'x-test-stepup': '1' }),
        })
        .send({ fields: ['PAN'], ...REASON });
    const refused = await send(false);
    expect(refused.status).toBe(401);
    expect(refused.body).toMatchObject({ code: 'ADMIN_STEP_UP_REQUIRED' });
    const ok = await send(true);
    expect(ok.status).toBe(200);
    expect(JSON.stringify(ok.body)).toContain('ABCDE1234F');
  });

  it('unknown commission or payout ids are 404 with their codes', async () => {
    const w = adminWorld();
    app = await boot(w.rest, w.a.service);
    const c = await request(app.getHttpServer())
      .post(`/admin/commissions/${UUID(9)}/approve`)
      .set({ 'x-test-admin': SUPER, 'x-test-perms': 'commission.approve' })
      .send(REASON);
    expect(c.status).toBe(404);
    expect(c.body).toMatchObject({ code: 'COMMISSION_NOT_FOUND' });
    const p = await request(app.getHttpServer())
      .get(`/admin/payouts/${UUID(9)}`)
      .set({ 'x-test-admin': PAYER, 'x-test-perms': 'payout.view' });
    expect(p.status).toBe(404);
    expect(p.body).toMatchObject({ code: 'PAYOUT_NOT_FOUND' });
  });

  it('payout create answers 201 when new and 200 when it already existed', async () => {
    const w = adminWorld();
    const create = jest
      .fn<Promise<unknown>, [unknown, unknown]>()
      .mockResolvedValueOnce({ payout: { id: UUID(3) }, created: true })
      .mockResolvedValueOnce({ payout: { id: UUID(3) }, created: false });
    const rest = new AgentAdminRestDeps(
      w.h.agentsAdmin,
      w.h.referralsAdmin,
      w.h.commissionsAdmin,
      { ...w.h.payoutsAdmin, create } as never,
    );
    app = await boot(rest, w.a.service);
    const send = () =>
      request(app.getHttpServer())
        .post('/admin/payouts')
        .set({
          'x-test-admin': PAYER,
          'x-test-perms': 'payout.execute',
          'x-test-stepup': '1',
        })
        .send({ agentId: UUID(1), period: '2026-11', ...REASON });
    expect((await send()).status).toBe(201);
    expect((await send()).status).toBe(200);
    const actor = create.mock.calls[0][0] as {
      userId: string;
      stepUpFresh: boolean;
      context: { requestId: string };
    };
    expect(actor).toMatchObject({ userId: PAYER, stepUpFresh: true });
    expect(typeof actor.context.requestId).toBe('string');
  });
});
