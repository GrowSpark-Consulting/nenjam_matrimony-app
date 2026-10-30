/**
 * The agent-facing services, built once from the real adapters, behind one
 * injection token (`AGENT_PROGRAM`), so the controllers have one dependency
 * and tests can swap the whole set for in-memory fakes.
 *
 * Deployment configuration read here (never a business value, never logged):
 *  - AGENT_JWT_SECRET signs agent access tokens (HS256, at least 32
 *    characters) and keys the stored hash of refresh tokens (an HMAC of it,
 *    so there is no second secret; rotating it signs every agent out).
 *    Missing or too short: `tokens` is null, every agent route answers 503
 *    AGENT_PROGRAM_UNAVAILABLE and startup logs a warning. The API starts.
 *  - AGENT_PII_ENCRYPTION_KEY seals the applicant's phone, the PAN and the
 *    payout details (32 bytes, base64). Missing: `piiSealing` is false, the
 *    routes that seal answer 503 and startup warns. MALFORMED:
 *    `parseSealingKey` throws and startup stops (a wrong key is a
 *    misconfiguration, not "off").
 */
import { createHmac } from 'node:crypto';
import { Logger, ServiceUnavailableException } from '@nestjs/common';
import { parseSealingKey } from '@app/common';
import type { PrismaClient } from '@app/database';
import type { AdminAuditService } from '../../admin/services/admin-audit.service';
import type { IdentifierHashService } from '../../platform/identifier-hash.service';
import type { OtpService } from '../../platform/otp/otp.service';
import type { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import {
  AdminAuditAdapter,
  IdentifierHashAdapter,
  SystemClock,
} from '../adapters/admin/agent-admin-platform.adapters';
import {
  AgentActorAuditAdapter,
  PlatformOtpAdapter,
  PlatformSettingsAdapter,
} from '../adapters/platform/agent-platform.adapters';
import { PrismaAgentApplicantRepository } from '../adapters/prisma/prisma-agent-applicant.repository';
import { PrismaAgentMemberRead } from '../adapters/prisma/prisma-agent-member-read';
import { PrismaAgentPayoutDetailsRepository } from '../adapters/prisma/prisma-agent-payout-details.repository';
import { PrismaAgentRefreshTokenRepository } from '../adapters/prisma/prisma-agent-refresh-token.repository';
import { PrismaAgentRepository } from '../adapters/prisma/prisma-agent.repository';
import { PrismaAgentUnitOfWork } from '../adapters/prisma/prisma-agent-unit-of-work';
import { PrismaReferralAttributionRepository } from '../adapters/prisma/prisma-referral-attribution.repository';
import { PrismaReferralCodeAttemptStore } from '../adapters/prisma/prisma-referral-code-attempt.store';
import { PrismaReferralCodeRepository } from '../adapters/prisma/prisma-referral-code.repository';
import { AgentMeService } from '../agent/agent-me.service';
import { AgentProfileBuilder } from '../agent/agent-profile-builder';
import { AgentApplicationService } from '../application/agent-application.service';
import {
  AgentJwtTokenSigner,
  MIN_AGENT_JWT_SECRET_LENGTH,
  type AgentTokenChecker,
} from '../auth/agent-jwt-token-signer';
import { AgentSessionIssuer } from '../auth/agent-session-issuer';
import { AgentSignInService } from '../auth/agent-sign-in.service';
import { PrismaCommissionPolicyRepository } from '../adapters/prisma/prisma-commission-policy.repository';
import { ActivePolicyHoldDays } from '../config/active-policy-hold-days';
import { AgentConfigService } from '../config/agent-config.service';
import { StaticAgentContent } from '../content/agent-content';
import { AgentPiiSealer } from '../crypto/agent-pii-sealer';
import type { AgentTokenSigner } from '../ports/agent-infra-ports';
import type { AgentSecretSealer } from '../ports/agent-secret-sealer.port';
import { AgentReferralCodeService } from '../referral/agent-referral-code.service';
import { AgentReferralService } from '../referral/agent-referral.service';

export const AGENT_PROGRAM = Symbol('AGENT_PROGRAM');

/** Deployment identifiers of agent access tokens (not secrets, not settings). */
export const AGENT_TOKEN_ISSUER = 'nenjam-api';
export const AGENT_TOKEN_AUDIENCE = 'nenjam-agent-portal';

export interface AgentProgram {
  signIn: AgentSignInService;
  application: AgentApplicationService;
  me: AgentMeService;
  config: AgentConfigService;
  referrals: AgentReferralService;
  referralCodes: AgentReferralCodeService;
  /** null: AGENT_JWT_SECRET is not usable, every agent route answers 503. */
  tokens: AgentTokenChecker | null;
  /** false: AGENT_PII_ENCRYPTION_KEY is not set, the sealing routes answer 503. */
  piiSealing: boolean;
  /** The opaque key the public code check is limited by (a hashed IP). */
  requesterKey(ip: string | undefined): string;
}

export function agentProgramUnavailable(): ServiceUnavailableException {
  return new ServiceUnavailableException({
    statusCode: 503,
    error: 'Service Unavailable',
    code: 'AGENT_PROGRAM_UNAVAILABLE',
    message: 'The agent program is not available yet.',
  });
}

export function refreshTokenPepperFrom(secret: string): string {
  return createHmac('sha256', secret)
    .update('agent.refresh_token_pepper.v1', 'utf8')
    .digest('base64url');
}

/** Stands in while a secret or key is missing; the controllers refuse first. */
const UNAVAILABLE_SIGNER: AgentTokenSigner = {
  sign: () => Promise.reject(agentProgramUnavailable()),
  verify: () => Promise.resolve(null),
};
const UNAVAILABLE_SEALER: AgentSecretSealer = {
  seal: () => {
    throw agentProgramUnavailable();
  },
  open: () => {
    throw agentProgramUnavailable();
  },
};

/** Housekeeping of expired applicant and attempt rows (not business values):
 *  the same batch and grace as the OTP service's own purge. */
const PURGE_BATCH = 100;
const PURGE_GRACE_MS = 24 * 60 * 60_000;

export interface AgentProgramDeps {
  prisma: PrismaClient;
  platformSettings: PlatformSettingsService;
  otp: OtpService;
  hashing: IdentifierHashService;
  adminAudit: AdminAuditService;
  env: Record<string, string | undefined>;
  logger?: Pick<Logger, 'warn'>;
}

/** The PII sealer for a parsed key; with no key every seal and open answers 503. */
export function agentPiiSealerFor(key: Buffer | null): AgentSecretSealer {
  return key ? new AgentPiiSealer(key) : UNAVAILABLE_SEALER;
}

export function buildAgentProgram(deps: AgentProgramDeps): AgentProgram {
  const logger = deps.logger ?? new Logger('AgentProgram');
  const { prisma } = deps;
  const clock = new SystemClock();
  const settings = new PlatformSettingsAdapter(deps.platformSettings);
  const hasher = new IdentifierHashAdapter(deps.hashing);
  const audit = new AgentActorAuditAdapter(
    new AdminAuditAdapter(prisma, deps.adminAudit),
  );
  const uow = new PrismaAgentUnitOfWork(prisma);
  const purge = { batchSize: PURGE_BATCH, graceMs: PURGE_GRACE_MS, clock };
  const agents = new PrismaAgentRepository(prisma);
  const codes = new PrismaReferralCodeRepository(prisma);
  const refreshTokens = new PrismaAgentRefreshTokenRepository(prisma);
  const applicants = new PrismaAgentApplicantRepository(prisma, purge);
  const attributions = new PrismaReferralAttributionRepository(prisma);
  const attempts = new PrismaReferralCodeAttemptStore(prisma, purge);
  const payoutDetails = new PrismaAgentPayoutDetailsRepository(prisma);
  const members = new PrismaAgentMemberRead(prisma, hasher, clock);
  const content = new StaticAgentContent();
  const profiles = new AgentProfileBuilder(content, codes);

  const secret = deps.env.AGENT_JWT_SECRET?.trim() ?? '';
  const jwt =
    secret.length >= MIN_AGENT_JWT_SECRET_LENGTH
      ? new AgentJwtTokenSigner(
          {
            secret,
            issuer: AGENT_TOKEN_ISSUER,
            audience: AGENT_TOKEN_AUDIENCE,
          },
          clock,
        )
      : null;
  if (!jwt) {
    logger.warn(
      `AGENT_JWT_SECRET is not set (or shorter than ${MIN_AGENT_JWT_SECRET_LENGTH} characters): the agent routes answer 503.`,
    );
  }
  const key = parseSealingKey(
    deps.env.AGENT_PII_ENCRYPTION_KEY,
    'AGENT_PII_ENCRYPTION_KEY',
  );
  if (!key) {
    logger.warn(
      'AGENT_PII_ENCRYPTION_KEY is not set: agent sign-in, application and payout details answer 503.',
    );
  }
  const sealer = agentPiiSealerFor(key);

  const options = {
    issuer: AGENT_TOKEN_ISSUER,
    audience: AGENT_TOKEN_AUDIENCE,
    // Never used while `tokens` is null: every route that would use it is refused.
    refreshTokenPepper: jwt ? refreshTokenPepperFrom(secret) : 'unavailable',
  };
  const issuer = new AgentSessionIssuer({
    signer: jwt ?? UNAVAILABLE_SIGNER,
    clock,
    settings,
    refreshTokens,
    profiles,
    options,
  });
  const me = new AgentMeService({
    agents,
    payoutDetails,
    profiles,
    sealer,
    uow,
    audit,
    clock,
  });

  return {
    signIn: new AgentSignInService({
      otp: new PlatformOtpAdapter(deps.otp),
      hasher,
      agents,
      refreshTokens,
      applicants,
      sealer,
      uow,
      audit,
      settings,
      clock,
      issuer,
      options,
    }),
    application: new AgentApplicationService({
      agents,
      refreshTokens,
      applicants,
      sealer,
      uow,
      audit,
      clock,
      issuer,
    }),
    me,
    config: new AgentConfigService(
      settings,
      content,
      new ActivePolicyHoldDays(
        new PrismaCommissionPolicyRepository(prisma),
        clock,
      ),
    ),
    referrals: new AgentReferralService({
      access: me,
      codes,
      attributions,
      members,
      content,
      settings,
    }),
    referralCodes: new AgentReferralCodeService({
      settings,
      attempts,
      codes,
      agents,
      attributions,
      members,
      uow,
      audit,
      clock,
    }),
    tokens: jwt,
    piiSealing: key !== null,
    requesterKey: (ip) => requesterKeyFor(deps.hashing, ip),
  };
}

/** A hashed IP (Shaaz's IP kind). An address the hasher cannot read shares
 *  one opaque bucket rather than ever being stored raw. His 503 (no peppers)
 *  passes through. */
export function requesterKeyFor(
  hashing: Pick<IdentifierHashService, 'hashIdentifier'>,
  ip: string | undefined,
): string {
  if (!ip) return 'ip:unknown';
  try {
    return hashing.hashIdentifier('IP', ip);
  } catch (error) {
    if (error instanceof RangeError) return 'ip:unreadable';
    throw error;
  }
}
