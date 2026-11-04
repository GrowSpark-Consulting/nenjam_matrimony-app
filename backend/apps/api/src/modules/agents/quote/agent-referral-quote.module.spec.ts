import { Global, Inject, Injectable, Module, Optional } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { ReferralQuoteProvider } from '@app/common';
import { type PrismaClient, PrismaService } from '@app/database';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { PlatformModule } from '../../platform/platform.module';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import {
  ageOnIstDate,
  PrismaAgentMemberRead,
} from '../adapters/prisma/prisma-agent-member-read';
import {
  AGENT_REFERRAL_QUOTE,
  type AgentReferralQuote,
} from '../agent-referral-quote.token';
import { FakeAgentClock } from '../testing/fake-agent-infra';
import { FakeAgentIdentifierHasher } from '../testing/fake-agent-platform';
import {
  AgentReferralQuoteModule,
  buildQuoteProvider,
  QUOTE_SETTING_KEYS,
  quoteUnavailableReason,
} from './agent-referral-quote.module';

const NOW = new Date('2026-10-29T10:00:00.000Z');

/** The six quote settings, as the seed sets them. */
const SEEDED: Record<string, unknown> = {
  'referral.member_discount_bps': 500,
  'referral.discount_only_in_credit_window': true,
  'referral.credit_window_days': 60,
  'referral.code_validation_ip_limit': 60,
  'referral.code_validation_code_limit': 20,
  'referral.code_validation_window_seconds': 3600,
};

const settingsWith = (values: Record<string, unknown>) => ({
  getMany: jest.fn((keys: readonly string[]) =>
    Promise.resolve(
      Object.fromEntries(
        keys.filter((k) => k in values).map((k) => [k, values[k]]),
      ),
    ),
  ),
});

// Compile-time: what is provided fits the checkout's provider type.
const fits = (q: AgentReferralQuote): ReferralQuoteProvider => q;

describe('quoteUnavailableReason', () => {
  it('names the missing piece, never a value', async () => {
    await expect(
      quoteUnavailableReason({ available: false }, settingsWith(SEEDED)),
    ).resolves.toBe('IDENTIFIER_HASH_PEPPERS is not set');
    const partial = { ...SEEDED };
    delete partial['referral.credit_window_days'];
    delete partial['referral.code_validation_window_seconds'];
    await expect(
      quoteUnavailableReason({ available: true }, settingsWith(partial)),
    ).resolves.toBe(
      'settings not set: referral.credit_window_days, referral.code_validation_window_seconds',
    );
    await expect(
      quoteUnavailableReason(
        { available: true },
        settingsWith({ ...SEEDED, 'referral.member_discount_bps': 10_001 }),
      ),
    ).resolves.toMatch(/referral\.member_discount_bps must be/);
  });

  it('is null when hashing and all six settings are there', async () => {
    const settings = settingsWith(SEEDED);
    await expect(
      quoteUnavailableReason({ available: true }, settings),
    ).resolves.toBeNull();
    expect(settings.getMany).toHaveBeenCalledWith(QUOTE_SETTING_KEYS);
  });
});

describe('buildQuoteProvider', () => {
  const prisma = {} as PrismaService;
  const logger = { warn: jest.fn(), log: jest.fn() };
  beforeEach(() => {
    logger.warn.mockClear();
    logger.log.mockClear();
  });

  it('without peppers or settings it provides null and warns', async () => {
    await expect(
      buildQuoteProvider(
        prisma,
        settingsWith({}) as unknown as PlatformSettingsService,
        { available: true } as IdentifierHashService,
        logger,
      ),
    ).resolves.toBeNull();
    expect(logger.warn).toHaveBeenCalledWith(
      expect.stringContaining('NOT provided') as string,
    );
  });

  it('with both it provides a quote service', async () => {
    const quote = await buildQuoteProvider(
      prisma,
      settingsWith(SEEDED) as unknown as PlatformSettingsService,
      { available: true } as IdentifierHashService,
      logger,
    );
    expect(quote).not.toBeNull();
    expect(typeof fits(quote as AgentReferralQuote).quote).toBe('function');
    expect(logger.warn).not.toHaveBeenCalled();
  });
});

@Injectable()
class CheckoutLike {
  constructor(
    @Optional()
    @Inject(AGENT_REFERRAL_QUOTE)
    readonly quote?: AgentReferralQuote | null,
  ) {}
}

@Global()
@Module({
  providers: [{ provide: PrismaService, useValue: {} }],
  exports: [PrismaService],
})
class StandInDatabaseModule {}

@Module({ providers: [CheckoutLike] })
class ConsumerModule {}

@Module({
  providers: [
    { provide: PlatformSettingsService, useValue: settingsWith({}) },
    { provide: IdentifierHashService, useValue: { available: false } },
  ],
  exports: [PlatformSettingsService, IdentifierHashService],
})
class StandInPlatformModule {}

describe('AgentReferralQuoteModule (global, as the checkout sees it)', () => {
  it('another module injects it optionally; unconfigured, it is falsy (no quote)', async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [
        StandInDatabaseModule,
        AgentReferralQuoteModule,
        ConsumerModule,
      ],
    })
      .overrideModule(PlatformModule)
      .useModule(StandInPlatformModule)
      .compile();
    expect(moduleRef.get(CheckoutLike).quote).toBeFalsy();
  });

  it('configured, the consumer gets the real service', async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [
        StandInDatabaseModule,
        AgentReferralQuoteModule,
        ConsumerModule,
      ],
    })
      .overrideModule(PlatformModule)
      .useModule(StandInPlatformModule)
      .overrideProvider(PlatformSettingsService)
      .useValue(settingsWith(SEEDED))
      .overrideProvider(IdentifierHashService)
      .useValue({ available: true })
      .compile();
    expect(typeof moduleRef.get(CheckoutLike).quote?.quote).toBe('function');
  });
});

describe('PrismaAgentMemberRead', () => {
  const hasher = new FakeAgentIdentifierHasher('test-secret');
  const clock = new FakeAgentClock(NOW);
  function db(user: unknown, payment: unknown) {
    return {
      user: { findFirst: jest.fn().mockResolvedValue(user) },
      paymentTransaction: { findFirst: jest.fn().mockResolvedValue(payment) },
    } as unknown as PrismaClient;
  }

  it('a member with a phone has its newest-pepper hash; no phone is null', async () => {
    const signedUp = new Date('2026-10-01T00:00:00Z');
    const read = new PrismaAgentMemberRead(
      db({ id: 'm1', phone: '+919000000002', createdAt: signedUp }, null),
      hasher,
      clock,
    );
    await expect(read.getMember('m1')).resolves.toEqual({
      memberId: 'm1',
      phoneHash: hasher.hash('PHONE', '+919000000002'),
      signedUpAt: signedUp,
      hasPaid: false,
    });
    const nophone = new PrismaAgentMemberRead(
      db({ id: 'm2', phone: null, createdAt: signedUp }, { id: 'p' }),
      hasher,
      clock,
    );
    await expect(nophone.getMember('m2')).resolves.toMatchObject({
      phoneHash: null,
      hasPaid: true,
    });
    await expect(
      new PrismaAgentMemberRead(db(null, null), hasher, clock).getMember('x'),
    ).resolves.toBeNull();
  });

  it('view fields: PURCHASED with the first paid plan, else from the profile', async () => {
    const profile = {
      firstName: 'Priya',
      lastName: 'Sharma',
      dob: new Date('1999-10-30T00:00:00Z'),
      currentCity: 'Madurai',
      isProfileComplete: true,
      profileCompletePct: 80,
    };
    const user = { phone: '+919000000002', createdAt: NOW, profile };
    const paidAt = new Date('2026-10-20T00:00:00Z');
    const paid = new PrismaAgentMemberRead(
      db(user, { paidAt, subscription: { plan: { displayName: 'Gold' } } }),
      hasher,
      clock,
    );
    await expect(paid.getReferralViewFields('m1')).resolves.toMatchObject({
      stage: 'PURCHASED',
      planName: 'Gold',
      purchasedAt: paidAt,
      age: 26,
      profileCompletenessPct: 80,
    });
    const complete = new PrismaAgentMemberRead(db(user, null), hasher, clock);
    await expect(complete.getReferralViewFields('m1')).resolves.toMatchObject({
      stage: 'PROFILE_COMPLETE',
      planName: null,
    });
    const noProfile = new PrismaAgentMemberRead(
      db({ ...user, profile: null }, null),
      hasher,
      clock,
    );
    await expect(noProfile.getReferralViewFields('m1')).resolves.toBeNull();
  });

  it('age is the calendar age on the Indian date', () => {
    const dob = new Date('2000-10-30T00:00:00Z');
    // 29 Oct 18:30 UTC is already 30 Oct in India: the birthday.
    expect(ageOnIstDate(dob, new Date('2026-10-29T18:29:00Z'))).toBe(25);
    expect(ageOnIstDate(dob, new Date('2026-10-29T18:30:00Z'))).toBe(26);
  });
});
