/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md):
 * GET /agent/config through the REAL wiring - `AgentProgramModule` and its
 * `buildAgentProgram` factory, the real `PlatformSettingsService` and the
 * Prisma adapters - against a throwaway LOCAL Postgres built from this
 * branch's migrations. The settings and commission policy v1 come from the
 * seed migrations, as in production; nothing is faked except the services
 * the config route never touches (OTP, hashing, audit, the member guard).
 *
 * Regression: the factory used to pass a placeholder policy that always
 * answered "no policy", so this route was 503 in production.
 */
import { Global, type INestApplication, Logger, Module } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import type { App } from 'supertest/types';
import { ApiValidationPipe, FirebaseAuthGuard } from '@app/common';
import { AppConfigModule, AppConfigService } from '@app/config';
import { PrismaService } from '@app/database';
import { FirebaseService } from '@app/firebase';
import { LocationService } from '../../reference-data/services/location.service';
import { ReligionService } from '../../reference-data/services/religion.service';
import { AdminModule } from '../../admin/admin.module';
import { AdminAuditService } from '../../admin/services/admin-audit.service';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { DailyJobRegistry } from '../../platform/jobs/daily-job.registry';
import { OtpService } from '../../platform/otp/otp.service';
import { PlatformModule } from '../../platform/platform.module';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import { PrismaAgentRepository } from '../adapters/prisma/prisma-agent.repository';
import { PrismaReferralCodeRepository } from '../adapters/prisma/prisma-referral-code.repository';
import {
  REFERRAL_SHARE_LINK_BASE_URL_KEY,
  referralShareLinkBaseUrlProblem,
} from '../settings/agent-share-link';
import {
  freshTestDatabase,
  openTestDatabase,
} from '../adapters/prisma/prisma-test-database';
import { SystemClock } from '../adapters/admin/agent-admin-platform.adapters';
import { AgentJwtTokenSigner } from '../auth/agent-jwt-token-signer';
import { AGENT_CONTENT } from '../content/agent-content';
import { AGENT_TOKEN_AUDIENCE, AGENT_TOKEN_ISSUER } from './agent-program';
import { AgentProgramModule } from './agent-program.module';

const db = openTestDatabase();
const prisma = db.prisma;

// Test-only value, not a secret.
const SECRET = 'test-only-agent-jwt-secret-not-real-0000';
const signer = new AgentJwtTokenSigner(
  {
    secret: SECRET,
    issuer: AGENT_TOKEN_ISSUER,
    audience: AGENT_TOKEN_AUDIENCE,
  },
  new SystemClock(),
);
const agents = new PrismaAgentRepository(prisma);

@Global()
@Module({
  providers: [{ provide: PrismaService, useValue: prisma }],
  exports: [PrismaService],
})
class TestDatabaseModule {}

@Module({
  providers: [{ provide: AdminAuditService, useValue: { record: jest.fn() } }],
  exports: [AdminAuditService],
})
class StandInAdminModule {}

@Module({
  providers: [
    // The REAL settings service, reading the seeded platform_settings rows.
    {
      provide: PlatformSettingsService,
      useFactory: () => new PlatformSettingsService(prisma as PrismaService),
    },
    { provide: IdentifierHashService, useValue: { available: false } },
    { provide: OtpService, useValue: {} },
    DailyJobRegistry,
  ],
  exports: [
    PlatformSettingsService,
    IdentifierHashService,
    OtpService,
    DailyJobRegistry,
  ],
})
class StandInPlatformModule {}

/** The config route reads neither; the factory only needs them to exist. */
@Global()
@Module({
  providers: [
    {
      provide: AppConfigService,
      useValue: { agentOtp: { dummyEnabled: false, dummyPhones: [] } },
    },
    { provide: FirebaseService, useValue: {} },
    { provide: LocationService, useValue: {} },
    { provide: ReligionService, useValue: {} },
  ],
  exports: [
    AppConfigService,
    FirebaseService,
    LocationService,
    ReligionService,
  ],
})
class StandInConfigModule {}

const saved = process.env.AGENT_JWT_SECRET;
let app: INestApplication<App>;

beforeAll(async () => {
  // The test client refuses any use before its first database exists.
  await freshTestDatabase(prisma);
  process.env.AGENT_JWT_SECRET = SECRET;
  const moduleRef = await Test.createTestingModule({
    imports: [TestDatabaseModule, AgentProgramModule],
  })
    .overrideModule(AdminModule)
    .useModule(StandInAdminModule)
    .overrideModule(PlatformModule)
    .useModule(StandInPlatformModule)
    .overrideModule(AppConfigModule)
    .useModule(StandInConfigModule)
    .overrideGuard(FirebaseAuthGuard)
    .useValue({ canActivate: () => false })
    .compile();
  app = moduleRef.createNestApplication<INestApplication<App>>();
  app.useGlobalPipes(
    new ApiValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );
  await app.init();
});

afterAll(async () => {
  await app?.close();
  await db.close();
  if (saved === undefined) delete process.env.AGENT_JWT_SECRET;
  else process.env.AGENT_JWT_SECRET = saved;
});

beforeEach(() => freshTestDatabase(prisma));

const T0 = new Date('2026-10-29T09:00:00.000Z');

async function tokenFor(
  scope: 'AGENT' | 'APPLICANT',
  sub: string,
): Promise<string> {
  const iat = Math.floor(Date.now() / 1000);
  return signer.sign({
    sub,
    scope,
    iss: AGENT_TOKEN_ISSUER,
    aud: AGENT_TOKEN_AUDIENCE,
    iat,
    exp: iat + 900,
  });
}

async function agentToken(status: string): Promise<string> {
  const id = '11111111-1111-4111-8111-000000000001';
  await agents.create({
    id,
    phoneHash: 'v1:agent-hash-1',
    phoneE164: '+919000000001',
    name: 'Ravi Kumar',
    city: 'Madurai',
    state: 'Tamil Nadu',
    panLast4: null,
    panSealed: null,
    createdAt: T0,
  });
  if (status !== 'PENDING_APPROVAL') {
    await agents.update(id, {
      status: status as never,
      // The database requires a reason on a REJECTED agent.
      ...(status === 'REJECTED' && { rejectionReason: 'Test reason' }),
    });
  }
  return tokenFor('AGENT', id);
}

const getConfig = (token: string) =>
  request(app.getHttpServer())
    .get('/agent/config')
    .set('Authorization', `Bearer ${token}`)
    .set('Accept-Version', '1');

describe('GET /agent/config with the real wiring', () => {
  it.each([
    'PENDING_APPROVAL',
    'ACTIVE',
    'SUSPENDED',
    'REJECTED',
    'TERMINATED',
  ])(
    'answers 200 for a %s agent, with the seeded settings and policy v1',
    async (status) => {
      const res = await getConfig(await agentToken(status));
      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        statusLabels: AGENT_CONTENT.statusLabels,
        stageLabels: AGENT_CONTENT.stageLabels,
        commissionStatusLabels: AGENT_CONTENT.commissionStatusLabels,
        payoutStatusLabels: AGENT_CONTENT.payoutStatusLabels,
        settings: {
          holdDays: 14,
          creditWindowDays: 60,
          minPayoutPaise: 50000,
          referredMemberDiscountPercent: 5,
        },
      });
      const shareMessages = (res.body as { shareMessages: unknown[] })
        .shareMessages;
      expect(shareMessages).toHaveLength(
        AGENT_CONTENT.shareMessageTemplates.length,
      );
      expect(JSON.stringify(shareMessages)).not.toContain('{discount_percent}');
      // Way 2, from the seeded rows: switched off, limit 10, 14 days.
      expect((res.body as { clients: unknown }).clients).toEqual({
        enabled: false,
        draftLimit: 10,
        expiryDays: 14,
      });
      expect(
        (res.body as { clientStatusLabels: unknown }).clientStatusLabels,
      ).toEqual(AGENT_CONTENT.clientStatusLabels);
      expect(Object.keys(res.body as object).sort()).toEqual([
        'clientStatusLabels',
        'clients',
        'commissionStatusLabels',
        'payoutStatusLabels',
        'settings',
        'shareMessages',
        'stageLabels',
        'statusLabels',
      ]);
    },
  );

  it('an APPLICANT token is 401 (the contract allows applicants only the application and GET /agent/me)', async () => {
    const res = await getConfig(
      await tokenFor('APPLICANT', 'v1:applicant-hash'),
    );
    expect(res.status).toBe(401);
  });

  it('no token is 401', async () => {
    const res = await request(app.getHttpServer()).get('/agent/config');
    expect(res.status).toBe(401);
  });

  it('a missing setting is 503, and the log names the key (never a value)', async () => {
    const warn = jest.spyOn(Logger.prototype, 'warn').mockImplementation();
    try {
      await prisma.platformSetting.delete({
        where: { key: 'referral.credit_window_days' },
      });
      const res = await getConfig(await agentToken('ACTIVE'));
      expect(res.status).toBe(503);
      expect(res.body).toMatchObject({ code: 'AGENT_PROGRAM_UNAVAILABLE' });
      expect(warn.mock.calls.map((c) => String(c[0]))).toContain(
        'Agent config is not available: missing referral.credit_window_days.',
      );
    } finally {
      warn.mockRestore();
    }
  });

  it('a malformed setting is 503 naming the key, not a 500', async () => {
    const warn = jest.spyOn(Logger.prototype, 'warn').mockImplementation();
    try {
      await prisma.platformSetting.update({
        where: { key: 'payout.minimum_amount_paise' },
        data: { value: 'not a number' },
      });
      const res = await getConfig(await agentToken('ACTIVE'));
      expect(res.status).toBe(503);
      expect(warn.mock.calls.map((c) => String(c[0]))).toContain(
        'Agent config is not available: invalid payout.minimum_amount_paise.',
      );
      expect(JSON.stringify(warn.mock.calls)).not.toContain('not a number');
    } finally {
      warn.mockRestore();
    }
  });
});

describe('GET /agent/referral-links with the real wiring', () => {
  const codes = new PrismaReferralCodeRepository(prisma);
  const BASE = 'https://testapp.nenjammatrimony.com';

  async function linksOf(token: string) {
    const res = await request(app.getHttpServer())
      .get('/agent/referral-links')
      .set('Authorization', `Bearer ${token}`)
      .set('Accept-Version', '1');
    expect(res.status).toBe(200);
    return (
      res.body as {
        items: Array<{
          link: string | null;
          qrPayload: string | null;
          shareMessages: Array<{ text: { en: string } }>;
        }>;
      }
    ).items;
  }

  async function activeAgentWithCode(): Promise<string> {
    const token = await agentToken('ACTIVE');
    await codes.create({
      id: '22222222-2222-4222-8222-000000000001',
      agentId: '11111111-1111-4111-8111-000000000001',
      code: 'NM7K2P9X',
      isPrimary: true,
      isActive: true,
      createdAt: T0,
    });
    return token;
  }

  it('the web address is seeded as JSON null, so link and qrPayload are null', async () => {
    const row = await prisma.platformSetting.findUnique({
      where: { key: REFERRAL_SHARE_LINK_BASE_URL_KEY },
    });
    expect(row?.value).toBeNull();
    const [item] = await linksOf(await activeAgentWithCode());
    expect(item).toMatchObject({ link: null, qrPayload: null });
    expect(item.shareMessages[0].text.en).not.toContain('https://');
  });

  it('once set, every link is {base}/?ref={code} and qrPayload equals it', async () => {
    await prisma.platformSetting.update({
      where: { key: REFERRAL_SHARE_LINK_BASE_URL_KEY },
      data: { value: BASE },
    });
    const [item] = await linksOf(await activeAgentWithCode());
    expect(item.link).toBe(`${BASE}/?ref=NM7K2P9X`);
    expect(item.qrPayload).toBe(item.link);
    expect(
      item.shareMessages[0].text.en.endsWith(`
${BASE}/?ref=NM7K2P9X`),
    ).toBe(true);
  });

  it('a stored value the rule refuses (written around the admin route) gives no link, not an error', async () => {
    await prisma.platformSetting.update({
      where: { key: REFERRAL_SHARE_LINK_BASE_URL_KEY },
      data: { value: 'https://agent.nenjammatrimony.com' },
    });
    const [item] = await linksOf(await activeAgentWithCode());
    expect(item).toMatchObject({ link: null, qrPayload: null });
  });

  it('the admin settings refuse a bad value with the registered validator and keep the stored null', async () => {
    const settings = new PlatformSettingsService(prisma as PrismaService);
    settings.registerValidator(
      REFERRAL_SHARE_LINK_BASE_URL_KEY,
      referralShareLinkBaseUrlProblem,
    );
    for (const value of [
      'https://agent.nenjammatrimony.com',
      `${BASE}/join`,
      'http://testapp.nenjammatrimony.com',
    ]) {
      await expect(
        settings.update({
          key: REFERRAL_SHARE_LINK_BASE_URL_KEY,
          value,
          expectedVersion: 1,
          reason: 'test',
          actorId: 'not-used',
        }),
      ).rejects.toMatchObject({ status: 400 });
    }
    const row = await prisma.platformSetting.findUnique({
      where: { key: REFERRAL_SHARE_LINK_BASE_URL_KEY },
    });
    expect([row?.value, row?.version]).toEqual([null, 1]);
  });
});
