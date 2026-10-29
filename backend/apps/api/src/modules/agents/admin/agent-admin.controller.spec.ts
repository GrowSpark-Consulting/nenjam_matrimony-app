/**
 * HTTP-level tests for `/admin/agents` (PR A), through Nest's real routing,
 * pipes (the global ApiValidationPipe, as in main.ts), the id pipe and our
 * error filter. Firebase and the admin session are stand-ins: the stand-in
 * guard reads the route's @RequirePermissions metadata like the real
 * AdminGuard does, so a missing permission is refused at the door, and the
 * service then checks again inside its transaction (also tested).
 *
 * The last block boots the real AgentsModule wiring (adapters built by its
 * factory) with AdminRouteCheck running, which refuses to start if any admin
 * route lacks a permission decorator.
 */
import {
  CanActivate,
  ExecutionContext,
  Get,
  INestApplication,
  Injectable,
  Module,
  UnauthorizedException,
  Global,
} from '@nestjs/common';
import { DiscoveryModule, Reflector } from '@nestjs/core';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import type { App } from 'supertest/types';
import { ApiValidationPipe, FirebaseAuthGuard } from '@app/common';
import { PrismaService } from '@app/database';
import { AdminModule } from '../../admin/admin.module';
import { adminForbidden } from '../../admin/auth/admin-auth.policy';
import type { AdminRequest } from '../../admin/auth/admin-request';
import { AdminRouteCheck } from '../../admin/auth/admin-route-check';
import {
  ADMIN_ROUTE_POLICY,
  type AdminRoutePolicy,
} from '../../admin/auth/admin-route-policy';
import { AdminController } from '../../admin/auth/admin-route.decorators';
import { AdminGuard } from '../../admin/auth/admin.guard';
import { AdminAuditService } from '../../admin/services/admin-audit.service';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { PlatformModule } from '../../platform/platform.module';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import { AgentsModule } from '../agents.module';
import {
  APPROVER,
  NOBODY,
  SEALED_DETAILS,
  SEALED_PAN,
  VIEWER,
  makeAgentAdminHarness,
  type AgentAdminHarness,
} from '../testing/agent-admin-agents-harness';
import { AgentAdminAgentsService } from './agent-admin-agents.service';

interface Body {
  code?: string;
  message?: unknown;
  codes?: unknown[];
  items?: unknown[];
  nextCursor?: string | null;
}
const bodyOf = (res: { body: unknown }): Body => res.body as Body;

/** Which permissions each stand-in staff member holds at the door. */
const DOOR: Record<string, string[]> = {
  [VIEWER]: ['agent.view'],
  [APPROVER]: ['agent.view', 'agent.approve'],
  [NOBODY]: [],
  // Holds agent.approve at the door but not in the database (a role removed a
  // moment ago): the service's in-transaction check must refuse.
  'staff-revoked': ['agent.view', 'agent.approve'],
};

@Injectable()
class StandInAdminGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(ctx: ExecutionContext): boolean {
    const req = ctx.switchToHttp().getRequest<AdminRequest>();
    const userId = req.headers['x-test-admin'];
    if (typeof userId !== 'string' || !(userId in DOOR)) {
      throw new UnauthorizedException();
    }
    const policy = this.reflector.get<AdminRoutePolicy | undefined>(
      ADMIN_ROUTE_POLICY,
      ctx.getHandler(),
    );
    const missing = (policy?.permissions ?? []).filter(
      (p) => !DOOR[userId].includes(p),
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
      stepUpVerifiedAt: null,
      roles: [],
      permissions: DOOR[userId] as never,
    };
    return true;
  }
}

const allow = { canActivate: () => true };

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
      useValue: { hashIdentifier: jest.fn(), hashIdentifierAll: jest.fn() },
    },
    {
      provide: PlatformSettingsService,
      useValue: { getMany: jest.fn(), registerValidator: jest.fn() },
    },
  ],
  exports: [IdentifierHashService, PlatformSettingsService],
})
class StandInPlatformModule {}

async function bootApp(
  service?: AgentAdminAgentsService,
  extraControllers: Array<new (...args: never[]) => unknown> = [],
): Promise<INestApplication<App>> {
  let builder = Test.createTestingModule({
    imports: [StandInDatabaseModule, AgentsModule],
    controllers: extraControllers,
  })
    .overrideModule(AdminModule)
    .useModule(StandInAdminModule)
    .overrideModule(PlatformModule)
    .useModule(StandInPlatformModule)
    .overrideGuard(FirebaseAuthGuard)
    .useValue(allow)
    .overrideGuard(AdminGuard)
    .useClass(StandInAdminGuard);
  if (service) {
    builder = builder
      .overrideProvider(AgentAdminAgentsService)
      .useValue(service);
  }
  const moduleRef = await builder.compile();
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

describe('/admin/agents over HTTP', () => {
  let h: AgentAdminHarness;
  let app: INestApplication<App>;

  beforeEach(async () => {
    h = makeAgentAdminHarness();
    h.permission.grant('staff-revoked', { module: 'agent', action: 'view' });
    app = await bootApp(h.service);
  });
  afterEach(() => app.close());

  const as = (user: string) => ({ 'x-test-admin': user });

  describe('permissions', () => {
    it.each([
      ['GET', '/admin/agents/summary'],
      ['GET', '/admin/agents'],
      ['GET', '/admin/agents/11111111-1111-4111-8111-000000000001'],
    ])(
      '%s %s without agent.view is 403 ADMIN_PERMISSION_DENIED',
      async (method, path) => {
        const res = await request(app.getHttpServer())
          [method.toLowerCase() as 'get'](path)
          .set(as(NOBODY));
        expect(res.status).toBe(403);
        expect(res.body).toMatchObject({
          statusCode: 403,
          error: 'Forbidden',
          code: 'ADMIN_PERMISSION_DENIED',
          missing: ['agent.view'],
        });
      },
    );

    it.each(['approve', 'reject'])(
      'POST %s with only agent.view is 403 and changes nothing',
      async (action) => {
        const { id } = await h.seedAgent(1);
        const res = await request(app.getHttpServer())
          .post(`/admin/agents/${id}/${action}`)
          .set(as(VIEWER))
          .send({ reason: 'Documents checked.' });
        expect(res.status).toBe(403);
        expect(res.body).toMatchObject({
          code: 'ADMIN_PERMISSION_DENIED',
          missing: ['agent.approve'],
        });
        expect((await h.agents.findById(id))?.status).toBe('PENDING_APPROVAL');
        expect(h.audit.entries).toHaveLength(0);
      },
    );

    it('a permission removed since the guard looked is refused inside the transaction', async () => {
      const { id } = await h.seedAgent(1);
      const res = await request(app.getHttpServer())
        .post(`/admin/agents/${id}/approve`)
        .set(as('staff-revoked'))
        .send({ reason: 'Documents checked.' });
      expect(res.status).toBe(403);
      expect(res.body).toMatchObject({
        code: 'ADMIN_PERMISSION_DENIED',
        missing: ['agent.approve'],
      });
      expect((await h.agents.findById(id))?.status).toBe('PENDING_APPROVAL');
      expect(h.audit.entries).toHaveLength(0);
    });
  });

  describe('ids and bodies', () => {
    it.each([
      ['GET', '/admin/agents/not-a-uuid'],
      ['POST', '/admin/agents/not-a-uuid/approve'],
      ['POST', '/admin/agents/123/reject'],
    ])('%s %s answers 400 VALIDATION_FAILED', async (method, path) => {
      const res = await request(app.getHttpServer())
        [method.toLowerCase() as 'get' | 'post'](path)
        .set(as(APPROVER))
        .send({ reason: 'Documents checked.' });
      expect(res.status).toBe(400);
      expect(res.body).toMatchObject({
        statusCode: 400,
        code: 'VALIDATION_FAILED',
      });
    });

    it.each([
      ['missing', {}],
      ['too short', { reason: 'ab' }],
      ['too long', { reason: 'x'.repeat(501) }],
      ['not a string', { reason: 42 }],
      ['an extra field', { reason: 'Documents checked.', note: 'x' }],
    ])(
      'a reason that is %s answers 400 VALIDATION_FAILED and changes nothing',
      async (_label, body) => {
        const { id } = await h.seedAgent(1);
        for (const action of ['approve', 'reject']) {
          const res = await request(app.getHttpServer())
            .post(`/admin/agents/${id}/${action}`)
            .set(as(APPROVER))
            .send(body);
          expect(res.status).toBe(400);
          expect(bodyOf(res).code).toBe('VALIDATION_FAILED');
        }
        expect((await h.agents.findById(id))?.status).toBe('PENDING_APPROVAL');
        expect(h.audit.entries).toHaveLength(0);
      },
    );

    it('a short or long reason is refused by the body check, before the service runs', async () => {
      const { id } = await h.seedAgent(1);
      for (const reason of ['ab', 'x'.repeat(501)]) {
        const res = await request(app.getHttpServer())
          .post(`/admin/agents/${id}/approve`)
          .set(as(APPROVER))
          .send({ reason });
        expect(res.status).toBe(400);
        // The pipe answers with its messages; the service answers with `fields`.
        expect(res.body).not.toHaveProperty('fields');
        expect(bodyOf(res).message).toEqual([
          expect.stringContaining('reason must be'),
        ]);
      }
    });

    it('a blank reason (spaces only) is VALIDATION_FAILED from the service', async () => {
      const { id } = await h.seedAgent(1);
      const res = await request(app.getHttpServer())
        .post(`/admin/agents/${id}/reject`)
        .set(as(APPROVER))
        .send({ reason: '     ' });
      expect(res.status).toBe(400);
      expect(res.body).toMatchObject({
        code: 'VALIDATION_FAILED',
        fields: ['reason'],
      });
    });

    it.each([
      ['a bad status', '?status=GONE'],
      ['a page size of 0', '?limit=0'],
      ['a page size of 101', '?limit=101'],
      ['a one-letter name', '?name=a'],
      ['an unknown filter', '?colour=red'],
    ])('the list refuses %s with VALIDATION_FAILED', async (_label, qs) => {
      const res = await request(app.getHttpServer())
        .get(`/admin/agents${qs}`)
        .set(as(VIEWER));
      expect(res.status).toBe(400);
      expect(bodyOf(res).code).toBe('VALIDATION_FAILED');
    });

    it('an unknown agent is 404 AGENT_NOT_FOUND', async () => {
      const res = await request(app.getHttpServer())
        .get('/admin/agents/11111111-1111-4111-8111-999999999999')
        .set(as(VIEWER));
      expect(res.status).toBe(404);
      expect(res.body).toEqual({
        statusCode: 404,
        error: 'Not Found',
        code: 'AGENT_NOT_FOUND',
        message: expect.any(String) as unknown,
      });
    });
  });

  describe('state', () => {
    it('approve answers 200 with the agent, its first code and an audit row', async () => {
      const { id } = await h.seedAgent(1);
      const res = await request(app.getHttpServer())
        .post(`/admin/agents/${id}/approve`)
        .set(as(APPROVER))
        .send({ reason: 'Documents checked.' });
      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({ id, status: 'ACTIVE' });
      expect(bodyOf(res).codes).toHaveLength(1);
      expect(h.audit.entries).toEqual([
        expect.objectContaining({
          actorId: APPROVER,
          action: 'agent.approve',
          reason: 'Documents checked.',
          context: expect.objectContaining({
            requestId: expect.any(String) as unknown,
          }) as unknown,
        }),
      ]);
    });

    it('a second approve is 409 AGENT_TRANSITION_NOT_ALLOWED with the status and the refusal', async () => {
      const { id } = await h.seedAgent(1);
      const approve = () =>
        request(app.getHttpServer())
          .post(`/admin/agents/${id}/approve`)
          .set(as(APPROVER))
          .send({ reason: 'Documents checked.' });
      await approve();
      const res = await approve();
      expect(res.status).toBe(409);
      expect(res.body).toMatchObject({
        statusCode: 409,
        error: 'Conflict',
        code: 'AGENT_TRANSITION_NOT_ALLOWED',
        agentStatus: 'ACTIVE',
        refusal: 'SAME_STATUS',
      });
      expect(h.audit.entries).toHaveLength(1);
    });

    it('reject of an active agent is 409; reject of an applicant keeps the reason', async () => {
      const active = await h.seedAgent(1, 'ACTIVE');
      const res = await request(app.getHttpServer())
        .post(`/admin/agents/${active.id}/reject`)
        .set(as(APPROVER))
        .send({ reason: 'Not eligible.' });
      expect(res.status).toBe(409);
      expect(res.body).toMatchObject({
        code: 'AGENT_TRANSITION_NOT_ALLOWED',
        agentStatus: 'ACTIVE',
      });
      const pending = await h.seedAgent(2);
      const ok = await request(app.getHttpServer())
        .post(`/admin/agents/${pending.id}/reject`)
        .set(as(APPROVER))
        .send({ reason: 'The PAN does not match.' });
      expect(ok.status).toBe(200);
      expect(ok.body).toMatchObject({
        status: 'REJECTED',
        rejectionReason: 'The PAN does not match.',
      });
    });

    it('a failed audit write is a failure and nothing changed (same transaction)', async () => {
      const { id } = await h.seedAgent(1);
      jest
        .spyOn(h.audit, 'record')
        .mockRejectedValueOnce(new Error('audit down'));
      const res = await request(app.getHttpServer())
        .post(`/admin/agents/${id}/approve`)
        .set(as(APPROVER))
        .send({ reason: 'Documents checked.' });
      expect(res.status).toBe(500);
      expect((await h.agents.findById(id))?.status).toBe('PENDING_APPROVAL');
      expect(await h.codes.listByAgent(id)).toHaveLength(0);
    });
  });

  describe('reads', () => {
    it('summary is not read as an id', async () => {
      await h.seedAgent(1);
      const res = await request(app.getHttpServer())
        .get('/admin/agents/summary')
        .set(as(VIEWER));
      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        byStatus: { PENDING_APPROVAL: 1 },
        commissionsReady: null,
        payoutsCreated: null,
      });
    });

    it('the list is { items, nextCursor } and pages', async () => {
      for (let n = 1; n <= 3; n++) await h.seedAgent(n);
      const first = await request(app.getHttpServer())
        .get('/admin/agents?limit=2')
        .set(as(VIEWER));
      expect(first.status).toBe(200);
      expect(Object.keys(bodyOf(first)).sort()).toEqual([
        'items',
        'nextCursor',
      ]);
      expect(bodyOf(first).items).toHaveLength(2);
      const second = await request(app.getHttpServer())
        .get(
          `/admin/agents?limit=2&cursor=${encodeURIComponent(bodyOf(first).nextCursor ?? '')}`,
        )
        .set(as(VIEWER));
      expect(bodyOf(second).items).toHaveLength(1);
      expect(bodyOf(second).nextCursor).toBeNull();
    });

    it('sealed values never appear in any answer', async () => {
      const { id, phone } = await h.seedAgent(1, 'ACTIVE');
      await h.payoutDetails.save({
        agentId: id,
        method: 'UPI',
        detailsSealed: SEALED_DETAILS,
        display: 'r***@okbank',
        verifiedAt: null,
        changedAt: new Date(),
      });
      const answers = await Promise.all(
        ['/admin/agents', `/admin/agents/${id}`, '/admin/agents/summary'].map(
          (p) => request(app.getHttpServer()).get(p).set(as(VIEWER)),
        ),
      );
      for (const res of answers) {
        expect(res.status).toBe(200);
        const text = JSON.stringify(res.body);
        for (const secret of [
          SEALED_PAN,
          SEALED_DETAILS,
          phone,
          'ABCDE1234F',
          'ravi@okbank',
        ]) {
          expect(text).not.toContain(secret);
        }
      }
    });
  });
});

describe('the API boots with the agents module (AdminRouteCheck)', () => {
  it('starts with the real AgentsModule wiring and every admin route declares its permission', async () => {
    const app = await bootApp();
    expect(app.get(AgentAdminAgentsService)).toBeInstanceOf(
      AgentAdminAgentsService,
    );
    await app.close();
  });

  it('CONTROL: a route without a permission decorator stops the start', async () => {
    @AdminController('admin/agents-unprotected')
    class UnprotectedController {
      @Get()
      open() {
        return 'open';
      }
    }
    await expect(
      bootApp(undefined, [UnprotectedController as never]),
    ).rejects.toThrow(
      /without @RequirePermissions\/@AllowAnyAdmin: UnprotectedController\.open/,
    );
  });

  it('every route of AgentAdminController declares exactly the contract permission', () => {
    const { AgentAdminController } = jest.requireActual<
      typeof import('./agent-admin.controller')
    >('./agent-admin.controller');
    const proto = AgentAdminController.prototype as unknown as Record<
      string,
      object
    >;
    const policies = Object.fromEntries(
      ['summary', 'list', 'get', 'approve', 'reject'].map((name) => [
        name,
        (
          Reflect.getMetadata(
            ADMIN_ROUTE_POLICY,
            proto[name],
          ) as AdminRoutePolicy
        )?.permissions,
      ]),
    );
    expect(policies).toEqual({
      summary: ['agent.view'],
      list: ['agent.view'],
      get: ['agent.view'],
      approve: ['agent.approve'],
      reject: ['agent.approve'],
    });
  });
});
