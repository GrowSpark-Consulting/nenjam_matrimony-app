import { INestApplication, Logger } from '@nestjs/common';
import request from 'supertest';
import type { App } from 'supertest/types';
import type { AppConfigService } from '@app/config';
import type { PrismaClient, PrismaService } from '@app/database';
import { AdminModule } from '../../admin/admin.module';
import {
  createAdminTestApp,
  provisionAndEnrol,
  type TestPerson,
} from '../../admin/tests/admin-test-harness';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from '../../profiles/tests/integration-schema-guard';
import { OTP_POLICY, OtpRateLimitError, OtpService } from '../otp/otp.service';
import { PlatformSettingsService } from '../settings/platform-settings.service';

describeIntegration('platform: sign-in codes and settings', () => {
  jest.setTimeout(90_000);
  let prisma: PrismaClient;

  const CODE = '246810';
  const PHONE = '+919800000001';
  const otherPhone = (n: number) => `+9198000001${String(n).padStart(2, '0')}`;

  beforeAll(async () => {
    jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    prisma = await connectIsolatedPrisma();
  });

  afterAll(async () => {
    await prisma.otpChallenge.deleteMany({
      where: { phoneE164: { startsWith: '+9198000' } },
    });
    await prisma.platformSetting.deleteMany({
      where: { key: { startsWith: 'itest.' } },
    });
    await prisma.$disconnect();
  });

  describe('OtpService', () => {
    let otp: OtpService;
    let clock = new Date('2026-10-29T10:00:00Z');
    const later = (ms: number) => {
      clock = new Date(clock.getTime() + ms);
      return clock;
    };

    beforeAll(async () => {
      await prisma.otpChallenge.deleteMany({
        where: { phoneE164: { startsWith: '+9198000' } },
      });
      otp = new OtpService(
        prisma as unknown as PrismaService,
        {
          isProduction: false,
          agentOtp: { dummyEnabled: true, dummyPhones: [], dummyCode: CODE },
        } as unknown as AppConfigService,
      );
    });

    it('verifies the right code once and returns the phone', async () => {
      const { challengeId, expiresAt } = await otp.send(
        'AGENT_SIGN_IN',
        PHONE,
        clock,
      );
      expect(expiresAt.getTime() - clock.getTime()).toBe(OTP_POLICY.codeTtlMs);
      const row = await prisma.otpChallenge.findUniqueOrThrow({
        where: { id: challengeId },
      });
      expect(row.codeHash).not.toContain(CODE);

      await expect(
        otp.verify('AGENT_SIGN_IN', challengeId, CODE, later(1_000)),
      ).resolves.toEqual({ ok: true, phoneE164: PHONE });
      await expect(
        otp.verify('AGENT_SIGN_IN', challengeId, CODE, later(1_000)),
      ).resolves.toEqual({ ok: false, reason: 'ALREADY_USED' });
    });

    it('answers NOT_FOUND for an unknown challenge', async () => {
      await expect(
        otp.verify(
          'AGENT_SIGN_IN',
          '00000000-0000-4000-8000-000000000000',
          CODE,
        ),
      ).resolves.toEqual({ ok: false, reason: 'NOT_FOUND' });
      await expect(
        otp.verify('AGENT_SIGN_IN', "'; drop table x; --", CODE),
      ).resolves.toEqual({ ok: false, reason: 'NOT_FOUND' });
    });

    it('rate-limits sends per phone and purpose, with a retry time', async () => {
      const phone = otherPhone(1);
      await otp.send('AGENT_SIGN_IN', phone, later(60_000));
      const refusal = otp.send('AGENT_SIGN_IN', phone, later(5_000));
      await expect(refusal).rejects.toBeInstanceOf(OtpRateLimitError);
      await expect(refusal).rejects.toMatchObject({ retryAfterSeconds: 25 });
      // Another phone is not affected.
      await expect(
        otp.send('AGENT_SIGN_IN', otherPhone(2), clock),
      ).resolves.toHaveProperty('challengeId');
    });

    it('lets parallel sends for one phone through only once', async () => {
      const phone = otherPhone(3);
      const at = later(60_000);
      const results = await Promise.allSettled(
        Array.from({ length: 5 }, () => otp.send('AGENT_SIGN_IN', phone, at)),
      );
      expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    });

    it('dies after the attempt limit, even for the right code', async () => {
      const { challengeId } = await otp.send(
        'AGENT_SIGN_IN',
        otherPhone(4),
        later(60_000),
      );
      for (let i = 0; i < OTP_POLICY.maxAttempts; i++) {
        await expect(
          otp.verify('AGENT_SIGN_IN', challengeId, '000000', clock),
        ).resolves.toEqual({ ok: false, reason: 'INVALID_CODE' });
      }
      await expect(
        otp.verify('AGENT_SIGN_IN', challengeId, CODE, clock),
      ).resolves.toEqual({ ok: false, reason: 'TOO_MANY_ATTEMPTS' });
    });

    it('never counts more guesses than the limit, however many run at once', async () => {
      const { challengeId } = await otp.send(
        'AGENT_SIGN_IN',
        otherPhone(5),
        later(60_000),
      );
      const guesses = await Promise.all(
        Array.from({ length: 20 }, (_, i) =>
          otp.verify('AGENT_SIGN_IN', challengeId, String(100000 + i), clock),
        ),
      );
      const compared = guesses.filter(
        (g) => !g.ok && g.reason === 'INVALID_CODE',
      );
      expect(compared).toHaveLength(OTP_POLICY.maxAttempts);
      const row = await prisma.otpChallenge.findUniqueOrThrow({
        where: { id: challengeId },
      });
      expect(row.attempts).toBe(OTP_POLICY.maxAttempts);
    });

    it('never verifies an expired code', async () => {
      const { challengeId } = await otp.send(
        'AGENT_SIGN_IN',
        otherPhone(6),
        later(60_000),
      );
      await expect(
        otp.verify(
          'AGENT_SIGN_IN',
          challengeId,
          CODE,
          later(OTP_POLICY.codeTtlMs + 1),
        ),
      ).resolves.toEqual({ ok: false, reason: 'EXPIRED' });
    });

    it('purges challenges expired for over a day when sending', async () => {
      const old = new Date(clock.getTime() - OTP_POLICY.purgeAfterMs - 60_000);
      const stale = await prisma.otpChallenge.create({
        data: {
          purpose: 'AGENT_SIGN_IN',
          phoneE164: otherPhone(7),
          codeHash: 'x',
          createdAt: new Date(old.getTime() - 1_000),
          expiresAt: old,
        },
      });
      await otp.send('AGENT_SIGN_IN', otherPhone(8), later(60_000));
      await expect(
        prisma.otpChallenge.findUnique({ where: { id: stale.id } }),
      ).resolves.toBeNull();
    });
  });

  describe('PlatformSettingsService', () => {
    let settings: PlatformSettingsService;

    beforeAll(async () => {
      await prisma.platformSetting.deleteMany({
        where: { key: { startsWith: 'itest.' } },
      });
      await prisma.platformSetting.createMany({
        data: [
          { key: 'itest.rate_bps', value: 500 },
          { key: 'itest.undecided', value: 'null' as never },
        ],
      });
      // JSON null, as a migration seed would write it.
      await prisma.$executeRaw`UPDATE "platform_settings" SET "value" = 'null'::jsonb WHERE "key" = 'itest.undecided'`;
      settings = new PlatformSettingsService(
        prisma as unknown as PrismaService,
      );
    });

    it('returns only requested keys that exist, JSON null included', async () => {
      await expect(
        settings.getMany([
          'itest.rate_bps',
          'itest.undecided',
          'itest.missing',
          'itest.rate_bps',
        ]),
      ).resolves.toEqual({ 'itest.rate_bps': 500, 'itest.undecided': null });
      await expect(settings.getMany([])).resolves.toEqual({});
    });

    it('refuses keys that do not look like settings (database CHECK)', async () => {
      await expect(
        prisma.platformSetting.create({ data: { key: 'Bad Key', value: 1 } }),
      ).rejects.toThrow();
    });
  });

  describe('admin API: GET and PUT /admin/settings', () => {
    let app: INestApplication<App>;
    const DOMAIN = '@platform-itest.local';
    const people: Record<string, TestPerson> = {
      root: { uid: 'plat-root', email: `root${DOMAIN}` },
      viewer: { uid: 'plat-viewer', email: `viewer${DOMAIN}` },
    };
    const sessions: Record<string, string> = {};
    const VIEWER_ROLE = 'ITEST_SYSTEM_VIEWER';
    const http = () => request(app.getHttpServer());
    const as = (who: string) => ({
      Authorization: `Bearer ${who}`,
      'X-Admin-Session': sessions[who] ?? '',
    });

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
      await cleanup();
      await prisma.platformSetting.upsert({
        where: { key: 'itest.discount_bps' },
        create: { key: 'itest.discount_bps', value: 500 },
        update: { value: 500, version: 1 },
      });
      const viewerRole = await prisma.role.create({
        data: { key: VIEWER_ROLE, name: 'System viewer (itest)' },
      });
      const systemView = await prisma.permission.findUniqueOrThrow({
        where: { key: 'system.view' },
      });
      await prisma.rolePermission.create({
        data: { roleId: viewerRole.id, permissionId: systemView.id },
      });
      app = await createAdminTestApp(prisma, people, [AdminModule]);
      sessions.root = (
        await provisionAndEnrol(app, prisma, 'root', people.root, 'SUPER_ADMIN')
      ).session;
      sessions.viewer = (
        await provisionAndEnrol(
          app,
          prisma,
          'viewer',
          people.viewer,
          VIEWER_ROLE,
        )
      ).session;
    });

    afterAll(async () => {
      await cleanup();
      await app?.close();
    });

    const put = (who: string, body: Record<string, unknown>) =>
      http()
        .put('/admin/settings/itest.discount_bps')
        .set(as(who))
        .send({ reason: 'integration test', ...body });

    it('lists settings for system.view', async () => {
      const res = await http().get('/admin/settings').set(as('viewer'));
      expect(res.status).toBe(200);
      expect(res.headers['cache-control']).toBe('no-store');
      const items = (res.body as { items: Array<{ key: string }> }).items;
      expect(items.map((i) => i.key)).toContain('itest.discount_bps');
    });

    it('refuses a change without config.edit', async () => {
      const res = await put('viewer', { value: 700, version: 1 });
      expect(res.status).toBe(403);
      expect(res.body).toMatchObject({ code: 'ADMIN_PERMISSION_DENIED' });
    });

    it('changes a value, bumps the version and audits old and new together', async () => {
      const res = await put('root', { value: 700, version: 1 });
      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        key: 'itest.discount_bps',
        value: 700,
        version: 2,
      });
      const audit = await prisma.auditLog.findFirstOrThrow({
        where: {
          action: 'platform_setting.update',
          entityId: 'itest.discount_bps',
        },
        orderBy: { createdAt: 'desc' },
      });
      expect(audit).toMatchObject({
        actorType: 'STAFF',
        reason: 'integration test',
        before: { value: 500, version: 1 },
        after: { value: 700, version: 2 },
      });
    });

    it('refuses a stale version with 409 and the current one', async () => {
      const res = await put('root', { value: 900, version: 1 });
      expect(res.status).toBe(409);
      expect(res.body).toMatchObject({
        code: 'SETTING_VERSION_CONFLICT',
        currentVersion: 2,
      });
    });

    it('stores JSON null as a value', async () => {
      const res = await put('root', { value: null, version: 2 });
      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({ value: null, version: 3 });
    });

    it('answers VALIDATION_FAILED without a value, version or reason', async () => {
      const missingValue = await put('root', { version: 3 });
      expect(missingValue.status).toBe(400);
      expect(missingValue.body).toMatchObject({ code: 'VALIDATION_FAILED' });
      const badVersion = await put('root', { value: 1, version: 0 });
      expect(badVersion.body).toMatchObject({ code: 'VALIDATION_FAILED' });
      const noReason = await http()
        .put('/admin/settings/itest.discount_bps')
        .set(as('root'))
        .send({ value: 1, version: 3 });
      expect(noReason.body).toMatchObject({ code: 'VALIDATION_FAILED' });
    });

    it('answers 404 for an unknown key', async () => {
      const res = await http()
        .put('/admin/settings/itest.nothing_here')
        .set(as('root'))
        .send({ value: 1, version: 1, reason: 'integration test' });
      expect(res.status).toBe(404);
      expect(res.body).toMatchObject({ code: 'SETTING_NOT_FOUND' });
    });

    it('needs a fresh authenticator code to change anything', async () => {
      await prisma.adminSession.updateMany({
        where: { adminAccount: { user: { email: people.root.email } } },
        data: { mfaVerifiedAt: new Date(Date.now() - 11 * 60_000) },
      });
      const res = await put('root', { value: 800, version: 3 });
      expect(res.status).toBe(401);
      expect(res.body).toMatchObject({ code: 'ADMIN_STEP_UP_REQUIRED' });
      // Reading still works without one.
      await http().get('/admin/settings').set(as('root')).expect(200);
    });
  });
});
