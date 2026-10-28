import {
  DynamicModule,
  Get,
  INestApplication,
  Logger,
  Module,
  ValidationPipe,
} from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes } from 'node:crypto';
import request from 'supertest';
import type { App } from 'supertest/types';
import { AppConfigService } from '@app/config';
import { PrismaService, type PrismaClient } from '@app/database';
import { FirebaseService } from '@app/firebase';
import { RedisService } from '@app/cache';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from '../../profiles/tests/integration-schema-guard';
import { AdminModule } from '../admin.module';
import {
  AdminController,
  RequirePermissions,
} from '../auth/admin-route.decorators';
import { hashOpaqueToken } from '../auth/secret-box';
import { base32Decode, hotp, totpStep } from '../auth/totp';
import {
  deactivateAdmin,
  grantAdminRole,
  ProvisioningError,
  revokeAdminRole,
} from '../provisioning/admin-provisioning';

/**
 * Staff access end to end, over HTTP, against a real Postgres: provisioning,
 * authenticator enrolment, sessions, RBAC and the audit trail. Only Firebase
 * token verification is a stand-in. The probe controller's routes stand for
 * any permission-gated admin endpoint.
 */
@AdminController('admin/itest-probe')
class ProbeController {
  @Get('plans')
  @RequirePermissions('plan.view')
  plans() {
    return { ok: true };
  }

  @Get('publish')
  @RequirePermissions('plan.publish')
  publish() {
    return { ok: true };
  }

  @Get('reveal')
  @RequirePermissions('member.pii.reveal')
  reveal() {
    return { ok: true };
  }
}

@Module({ imports: [AdminModule], controllers: [ProbeController] })
class ProbeModule {}

describeIntegration('admin access over HTTP', () => {
  jest.setTimeout(60_000);
  let app: INestApplication<App>;
  let prisma: PrismaClient;

  const DOMAIN = '@admin-itest.local';
  const VIEWER_ROLE = 'ITEST_ADMIN_VIEWER';
  const people = {
    member: { uid: 'adm-itest-member', email: `member${DOMAIN}` },
    placeholder: {
      uid: 'adm-itest-placeholder',
      email: `placeholder${DOMAIN}`,
    },
    sa: { uid: 'adm-itest-super', email: `super${DOMAIN}` },
    viewer: { uid: 'adm-itest-viewer', email: `viewer${DOMAIN}` },
  } as const;
  type Person = keyof typeof people;

  const verifyIdToken = jest.fn((token: string) => {
    const person = people[token as Person];
    return person
      ? Promise.resolve({ uid: person.uid, email: person.email })
      : Promise.reject(new Error('invalid token'));
  });

  const http = () => request(app.getHttpServer());
  /** A JSON response body, typed for property access. */
  const body = (res: { body: unknown }) => res.body as Record<string, unknown>;
  const as = (who: Person, session?: string) => ({
    Authorization: `Bearer ${who}`,
    ...(session ? { 'X-Admin-Session': session } : {}),
  });

  async function accountOf(who: Person) {
    return prisma.adminAccount.findFirstOrThrow({
      where: { user: { email: people[who].email } },
    });
  }

  /** The current code for [secret]; clears the replay marker first so a test
   *  can sign in twice inside one 30-second step. */
  async function freshCode(who: Person, secret: string): Promise<string> {
    const account = await accountOf(who);
    await prisma.adminAccount.update({
      where: { id: account.id },
      data: { mfaLastUsedStep: null },
    });
    return hotp(base32Decode(secret), totpStep(Date.now()));
  }

  /** Provision → enrol over HTTP → session token. */
  async function provisionAndEnrol(who: Person, roleKey: string) {
    const { enrollmentCode } = await grantAdminRole(prisma, {
      firebaseUid: people[who].uid,
      email: people[who].email,
      roleKey,
      reason: 'integration test',
    });
    const started = await http()
      .post('/admin/auth/mfa/enrollment')
      .set(as(who))
      .send({ enrollmentCode })
      .expect(201);
    const secret = body(started).secret as string;
    const confirmed = await http()
      .post('/admin/auth/mfa/enrollment/confirm')
      .set(as(who))
      .send({ enrollmentCode, code: await freshCode(who, secret) })
      .expect(201);
    return {
      secret,
      enrollmentCode: enrollmentCode!,
      session: body(confirmed).sessionToken as string,
    };
  }

  async function cleanup() {
    const users = await prisma.user.findMany({
      where: { email: { endsWith: DOMAIN } },
      select: { id: true },
    });
    const ids = users.map((u) => u.id);
    await prisma.auditLog.deleteMany({ where: { actorId: { in: ids } } });
    await prisma.user.deleteMany({ where: { id: { in: ids } } });
    await prisma.role.deleteMany({ where: { key: VIEWER_ROLE } });
  }

  beforeAll(async () => {
    jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    prisma = await connectIsolatedPrisma();
    await cleanup();

    const infra: DynamicModule = {
      module: class TestInfraModule {},
      global: true,
      providers: [
        { provide: PrismaService, useValue: prisma },
        { provide: FirebaseService, useValue: { verifyIdToken } },
        // "Not ready": the auth guard's cache fails open to the database.
        {
          provide: RedisService,
          useValue: { getClient: () => ({ status: 'connecting' }) },
        },
      ],
      exports: [PrismaService, FirebaseService, RedisService],
    };
    const moduleRef = await Test.createTestingModule({
      imports: [infra, AdminModule, ProbeModule],
    })
      // AdminModule imports AppConfigModule itself; replace it everywhere.
      .overrideProvider(AppConfigService)
      .useValue({
        admin: { mfaEncryptionKey: randomBytes(32).toString('base64') },
      })
      .compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        transform: true,
        forbidNonWhitelisted: true,
      }),
    );
    await app.init();

    // A member, and an admin row like the old seeder's placeholder: role
    // ADMIN, legacy JSON grants, never provisioned (so inactive).
    await prisma.user.create({
      data: {
        firebaseUid: people.member.uid,
        email: people.member.email,
        status: 'ACTIVE',
      },
    });
    await prisma.user.create({
      data: {
        firebaseUid: people.placeholder.uid,
        email: people.placeholder.email,
        role: 'ADMIN',
        status: 'ACTIVE',
        adminAccount: { create: { permissions: { subscriptions: ['write'] } } },
      },
    });
    const viewer = await prisma.role.create({
      data: { key: VIEWER_ROLE, name: 'Integration viewer' },
    });
    const planView = await prisma.permission.findUniqueOrThrow({
      where: { key: 'plan.view' },
    });
    await prisma.rolePermission.create({
      data: { roleId: viewer.id, permissionId: planView.id },
    });
  });

  afterAll(async () => {
    await app?.close();
    if (prisma) await cleanup();
    await prisma?.$disconnect();
  });

  describe('who gets in at all', () => {
    it('401 without a Firebase token', async () => {
      await http().get('/admin/me').expect(401);
    });

    it('403 for a member, and the attempt is audited', async () => {
      const res = await http().get('/admin/me').set(as('member')).expect(403);
      expect(body(res).code).toBe('ADMIN_ACCESS_REQUIRED');
      const member = await prisma.user.findUniqueOrThrow({
        where: { email: people.member.email },
      });
      expect(
        await prisma.auditLog.count({
          where: {
            actorId: member.id,
            actorType: 'MEMBER',
            action: 'admin.access.denied',
            reason: 'NOT_STAFF',
          },
        }),
      ).toBeGreaterThan(0);
    });

    it('403 for an unprovisioned admin row holding only legacy JSON grants', async () => {
      const res = await http()
        .get('/admin/me')
        .set(as('placeholder'))
        .expect(403);
      expect(body(res).code).toBe('ADMIN_ACCESS_REQUIRED');
      // ...including on the sign-in steps.
      await http()
        .post('/admin/auth/session')
        .set(as('placeholder'))
        .send({ code: '123456' })
        .expect(403);
    });

    it('refuses to make a member with a profile into an admin', async () => {
      const member = await prisma.user.findUniqueOrThrow({
        where: { email: people.member.email },
      });
      await prisma.userProfile.create({
        data: {
          userId: member.id,
          firstName: 'Itest',
          lastName: 'Member',
          dob: new Date('1995-01-01'),
          gender: 'FEMALE',
          religion: 'HINDU',
          currentCity: 'Chennai',
          currentState: 'Tamil Nadu',
        },
      });
      await expect(
        grantAdminRole(prisma, {
          firebaseUid: people.member.uid,
          email: people.member.email,
          roleKey: 'SUPER_ADMIN',
          reason: 'should be refused',
        }),
      ).rejects.toBeInstanceOf(ProvisioningError);
    });
  });

  describe('a provisioned super admin', () => {
    let secret: string;
    let session: string;
    let enrollmentCode: string;

    it('needs the authenticator step before anything else (401)', async () => {
      const grant = await grantAdminRole(prisma, {
        firebaseUid: people.sa.uid,
        email: people.sa.email,
        roleKey: 'SUPER_ADMIN',
        reason: 'integration test',
      });
      expect(grant.enrollmentCode).toMatch(/^[2-9A-Z]{5}-[2-9A-Z]{5}$/);
      enrollmentCode = grant.enrollmentCode!;

      const res = await http().get('/admin/me').set(as('sa')).expect(401);
      expect(body(res).code).toBe('ADMIN_SESSION_REQUIRED');
    });

    it('cannot enrol without the one-time enrolment code', async () => {
      const res = await http()
        .post('/admin/auth/mfa/enrollment')
        .set(as('sa'))
        .send({ enrollmentCode: 'AAAAA-AAAAA' })
        .expect(403);
      expect(body(res).code).toBe('ADMIN_ENROLLMENT_CODE_INVALID');
    });

    it('enrols with it; the secret is stored encrypted, the code is spent', async () => {
      const started = await http()
        .post('/admin/auth/mfa/enrollment')
        .set(as('sa'))
        .send({ enrollmentCode: enrollmentCode.toLowerCase() })
        .expect(201);
      secret = body(started).secret as string;
      expect(body(started).otpauthUri).toContain('otpauth://totp/');
      const stored = await accountOf('sa');
      expect(stored.mfaSecretEncrypted).toMatch(/^v1\./);
      expect(stored.mfaSecretEncrypted).not.toContain(secret);

      const confirmed = await http()
        .post('/admin/auth/mfa/enrollment/confirm')
        .set(as('sa'))
        .send({ enrollmentCode, code: await freshCode('sa', secret) })
        .expect(201);
      session = body(confirmed).sessionToken as string;
      expect(body(confirmed).idleTimeoutSeconds).toBe(1800);

      const again = await http()
        .post('/admin/auth/mfa/enrollment')
        .set(as('sa'))
        .send({ enrollmentCode })
        .expect(403);
      expect(body(again).code).toBe('ADMIN_MFA_ALREADY_ENROLLED');
      expect((await accountOf('sa')).mfaEnrollmentCodeHash).toBeNull();
    });

    it('GET /admin/me returns its roles and every permission', async () => {
      const res = await http()
        .get('/admin/me')
        .set(as('sa', session))
        .expect(200);
      expect(body(res).roles).toEqual([
        { key: 'SUPER_ADMIN', name: 'Super Admin' },
      ]);
      expect(body(res).permissions).toHaveLength(48);
      expect(body(res).permissions).toContain('agent.approve');
      expect(body(res).email).toBe(people.sa.email);
    });

    it('never accepts the same authenticator code twice', async () => {
      const code = await freshCode('sa', secret);
      await http()
        .post('/admin/auth/session')
        .set(as('sa'))
        .send({ code })
        .expect(201);
      const replay = await http()
        .post('/admin/auth/session')
        .set(as('sa'))
        .send({ code })
        .expect(401);
      expect(body(replay).code).toBe('ADMIN_MFA_INVALID_CODE');
    });

    it("a session only works with its own admin's Firebase token", async () => {
      await http().get('/admin/me').set(as('member', session)).expect(403);
      const viewerGrant = await grantAdminRole(prisma, {
        firebaseUid: people.viewer.uid,
        email: people.viewer.email,
        roleKey: VIEWER_ROLE,
        reason: 'integration test',
      });
      expect(viewerGrant.enrollmentCode).not.toBeNull();
      const res = await http()
        .get('/admin/me')
        .set(as('viewer', session))
        .expect(401);
      expect(body(res).code).toBe('ADMIN_SESSION_INVALID');
    });

    it('sensitive permissions need a recent code (step-up)', async () => {
      await http()
        .get('/admin/itest-probe/reveal')
        .set(as('sa', session))
        .expect(200);

      await prisma.adminSession.updateMany({
        where: { adminAccountId: (await accountOf('sa')).id, revokedAt: null },
        data: { mfaVerifiedAt: new Date(Date.now() - 11 * 60_000) },
      });
      const stale = await http()
        .get('/admin/itest-probe/reveal')
        .set(as('sa', session))
        .expect(401);
      expect(body(stale).code).toBe('ADMIN_STEP_UP_REQUIRED');

      await http()
        .post('/admin/auth/step-up')
        .set(as('sa', session))
        .send({ code: await freshCode('sa', secret) })
        .expect(200);
      await http()
        .get('/admin/itest-probe/reveal')
        .set(as('sa', session))
        .expect(200);
    });

    it('an idle session ends', async () => {
      const code = await freshCode('sa', secret);
      const idle = body(
        await http()
          .post('/admin/auth/session')
          .set(as('sa'))
          .send({ code })
          .expect(201),
      ).sessionToken as string;
      await prisma.adminSession.update({
        where: { tokenHash: hashOpaqueToken(idle) },
        data: { lastSeenAt: new Date(Date.now() - 31 * 60_000) },
      });
      const res = await http().get('/admin/me').set(as('sa', idle)).expect(401);
      expect(body(res).code).toBe('ADMIN_SESSION_INVALID');
    });

    it('logout ends the session', async () => {
      await http()
        .post('/admin/auth/logout')
        .set(as('sa', session))
        .expect(204);
      await http().get('/admin/me').set(as('sa', session)).expect(401);
    });
  });

  describe('permissions come from roles, checked on every request', () => {
    let session: string;
    let secret: string;

    beforeAll(async () => {
      ({ session, secret } = await provisionAndEnrol('viewer', VIEWER_ROLE));
    });

    it('allows what the role grants and refuses the rest, with an audit row', async () => {
      await http()
        .get('/admin/itest-probe/plans')
        .set(as('viewer', session))
        .expect(200);
      const res = await http()
        .get('/admin/itest-probe/publish')
        .set(as('viewer', session))
        .expect(403);
      expect(res.body).toMatchObject({
        statusCode: 403,
        code: 'ADMIN_PERMISSION_DENIED',
        missing: ['plan.publish'],
      });
      const viewer = await prisma.user.findUniqueOrThrow({
        where: { email: people.viewer.email },
      });
      const denied = await prisma.auditLog.findFirst({
        where: { actorId: viewer.id, reason: 'MISSING_PERMISSION' },
        orderBy: { createdAt: 'desc' },
      });
      expect(denied?.entityId).toBe('GET /admin/itest-probe/publish');
      expect(denied?.requestId).toEqual(expect.any(String));
    });

    it('a removed role is refused on the very next request', async () => {
      await revokeAdminRole(prisma, {
        email: people.viewer.email,
        roleKey: VIEWER_ROLE,
        reason: 'integration test',
      });
      await http()
        .get('/admin/itest-probe/plans')
        .set(as('viewer', session))
        .expect(403);
      await grantAdminRole(prisma, {
        firebaseUid: people.viewer.uid,
        email: people.viewer.email,
        roleKey: VIEWER_ROLE,
        reason: 'integration test',
      });
      await http()
        .get('/admin/itest-probe/plans')
        .set(as('viewer', session))
        .expect(200);
    });

    it('locks the second factor after five wrong codes', async () => {
      for (let i = 0; i < 5; i++) {
        await http()
          .post('/admin/auth/session')
          .set(as('viewer'))
          .send({ code: '000000' })
          .expect(401);
      }
      const locked = await http()
        .post('/admin/auth/session')
        .set(as('viewer'))
        .send({ code: await freshCode('viewer', secret) })
        .expect(429);
      expect(body(locked).code).toBe('ADMIN_MFA_LOCKED');
      expect(body(locked).retryAfterSeconds).toBeGreaterThan(0);
      await prisma.adminAccount.update({
        where: { id: (await accountOf('viewer')).id },
        data: { mfaLockedUntil: null },
      });
    });

    it('deactivation ends every session immediately', async () => {
      const { sessionsEnded } = await deactivateAdmin(prisma, {
        email: people.viewer.email,
        reason: 'integration test',
      });
      expect(sessionsEnded).toBeGreaterThan(0);
      const res = await http()
        .get('/admin/me')
        .set(as('viewer', session))
        .expect(403);
      expect(body(res).code).toBe('ADMIN_ACCESS_REQUIRED');
    });

    it('provisioning is audited with a reason and no actor', async () => {
      const account = await accountOf('viewer');
      const rows = await prisma.auditLog.findMany({
        where: {
          entityId: account.id,
          action: { startsWith: 'admin.provision.' },
        },
        orderBy: { createdAt: 'asc' },
      });
      expect(rows.map((r) => r.action)).toEqual([
        'admin.provision.grant', // first grant (no authenticator yet)
        'admin.provision.grant', // re-run: same role, new enrolment code
        'admin.provision.revoke',
        'admin.provision.grant',
        'admin.provision.deactivate',
      ]);
      expect(
        rows.every(
          (r) =>
            r.actorId === null &&
            r.actorType === 'SYSTEM' &&
            r.reason === 'integration test',
        ),
      ).toBe(true);
      await prisma.auditLog.deleteMany({ where: { entityId: account.id } });
    });
  });
});
