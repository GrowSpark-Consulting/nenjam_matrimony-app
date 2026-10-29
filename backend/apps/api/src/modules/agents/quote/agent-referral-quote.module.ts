/**
 * Provides `AgentReferralQuoteService` to the checkout under
 * AGENT_REFERRAL_QUOTE, from a GLOBAL module (SubscriptionModule cannot
 * import AgentsModule: AgentsModule → AdminModule → SubscriptionModule).
 *
 * Not an agent route: it does NOT depend on AGENT_PROGRAM_ENABLED, and it
 * wires only what the quote reads (settings, codes, agents, attributions,
 * the member's verified phone hash and whether they have paid) plus the
 * attempt counter a typed code uses.
 *
 * SAFE BY DEFAULT. The checkout turns ANY quote error into "checkout
 * unavailable" for every purchase, so the real service is provided only when
 * it can answer: identifier hashing is configured (IDENTIFIER_HASH_PEPPERS)
 * and the six settings the quote reads are set and valid. Otherwise the
 * provider is `null`, which the checkout treats as "no quote" (list price; a
 * typed code gets 422 PROMO_CODES_UNAVAILABLE), and startup logs which part
 * is missing. Checked at startup: after the settings seed is applied the API
 * needs a restart (every Render deploy restarts it).
 */
import { Global, Logger, Module } from '@nestjs/common';
import { PrismaService } from '@app/database';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { PlatformModule } from '../../platform/platform.module';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import {
  IdentifierHashAdapter,
  SystemClock,
} from '../adapters/admin/agent-admin-platform.adapters';
import { PrismaAgentMemberRead } from '../adapters/prisma/prisma-agent-member-read';
import { PrismaAgentRepository } from '../adapters/prisma/prisma-agent.repository';
import { PrismaReferralAttributionRepository } from '../adapters/prisma/prisma-referral-attribution.repository';
import { PrismaReferralCodeAttemptStore } from '../adapters/prisma/prisma-referral-code-attempt.store';
import { PrismaReferralCodeRepository } from '../adapters/prisma/prisma-referral-code.repository';
import {
  AGENT_REFERRAL_QUOTE,
  type AgentReferralQuote,
} from '../agent-referral-quote.token';
import { AgentReferralQuoteService } from '../referral/agent-referral-quote.service';
import {
  parseAgentProgramSettings,
  REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY,
  REFERRAL_CREDIT_WINDOW_DAYS_KEY,
  REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY,
  REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
} from '../settings/agent-program-settings';

/** Every setting the quote (and its attempt limit) reads. */
export const QUOTE_SETTING_KEYS = [
  REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
  REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY,
  REFERRAL_CREDIT_WINDOW_DAYS_KEY,
  REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY,
] as const;

/** Housekeeping of expired attempt rows (not business values): the same
 *  batch and grace as the OTP service's own purge. */
const PURGE_BATCH = 100;
const PURGE_GRACE_MS = 24 * 60 * 60_000;

/** Why the quote cannot be provided yet, or null when it can. Names keys and
 *  variables only, never values. */
export async function quoteUnavailableReason(
  hashing: Pick<IdentifierHashService, 'available'>,
  settings: Pick<PlatformSettingsService, 'getMany'>,
): Promise<string | null> {
  if (!hashing.available) return 'IDENTIFIER_HASH_PEPPERS is not set';
  const raw = await settings.getMany(QUOTE_SETTING_KEYS);
  const wanted = new Set<string>(QUOTE_SETTING_KEYS);
  try {
    const { missing } = parseAgentProgramSettings(raw);
    const notSet = missing.filter((key) => wanted.has(key));
    return notSet.length > 0 ? `settings not set: ${notSet.join(', ')}` : null;
  } catch (error) {
    if (error instanceof RangeError) return error.message;
    throw error;
  }
}

export async function buildQuoteProvider(
  prisma: PrismaService,
  settings: PlatformSettingsService,
  hashing: IdentifierHashService,
  logger: Pick<Logger, 'warn' | 'log'> = new Logger('AgentReferralQuote'),
): Promise<AgentReferralQuote | null> {
  const reason = await quoteUnavailableReason(hashing, settings);
  if (reason !== null) {
    logger.warn(
      `Referral quote NOT provided (${reason}): checkout charges the list price and refuses typed codes.`,
    );
    return null;
  }
  const clock = new SystemClock();
  const hasher = new IdentifierHashAdapter(hashing);
  logger.log('Referral quote provided to the checkout.');
  return new AgentReferralQuoteService({
    settings: { getMany: (keys) => settings.getMany(keys) },
    attempts: new PrismaReferralCodeAttemptStore(prisma, {
      batchSize: PURGE_BATCH,
      graceMs: PURGE_GRACE_MS,
      clock,
    }),
    codes: new PrismaReferralCodeRepository(prisma),
    agents: new PrismaAgentRepository(prisma),
    attributions: new PrismaReferralAttributionRepository(prisma),
    members: new PrismaAgentMemberRead(prisma, hasher, clock),
    clock,
  });
}

@Global()
@Module({
  imports: [PlatformModule],
  providers: [
    {
      provide: AGENT_REFERRAL_QUOTE,
      inject: [PrismaService, PlatformSettingsService, IdentifierHashService],
      useFactory: (
        prisma: PrismaService,
        settings: PlatformSettingsService,
        hashing: IdentifierHashService,
      ) => buildQuoteProvider(prisma, settings, hashing),
    },
  ],
  exports: [AGENT_REFERRAL_QUOTE],
})
export class AgentReferralQuoteModule {}
