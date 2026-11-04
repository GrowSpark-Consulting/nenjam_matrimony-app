/**
 * The admin services behind the remaining admin routes, built once from the
 * real adapters (Prisma, admin RBAC and audit, platform settings and
 * hashing). One injectable holder so the controllers have one dependency and
 * tests can swap the set for fakes.
 *
 * AGENT_PII_ENCRYPTION_KEY seals and opens agent PAN and payout details
 * (reveal, the payout destination). Missing: those reads answer 503
 * AGENT_PROGRAM_UNAVAILABLE and startup warns; malformed: startup stops
 * (`parseSealingKey`). The key is never logged.
 */
import { Logger, ServiceUnavailableException } from '@nestjs/common';
import { parseSealingKey } from '@app/common';
import type { PrismaClient } from '@app/database';
import type { AdminAuditService } from '../../admin/services/admin-audit.service';
import type { IdentifierHashService } from '../../platform/identifier-hash.service';
import type { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import {
  AdminAuditAdapter,
  AdminPermissionAdapter,
  IdentifierHashAdapter,
  SystemClock,
} from '../adapters/admin/agent-admin-platform.adapters';
import { PrismaAgentLedgerRepository } from '../adapters/prisma/prisma-agent-ledger.repository';
import { PrismaAgentPayoutDetailsRepository } from '../adapters/prisma/prisma-agent-payout-details.repository';
import { PrismaAgentPayoutRepository } from '../adapters/prisma/prisma-agent-payout.repository';
import { PrismaAgentRepository } from '../adapters/prisma/prisma-agent.repository';
import {
  NO_MEMBER_PROFILE_VERIFICATION,
  PrismaAgentStatusHistory,
} from '../adapters/prisma/prisma-agent-status-history';
import { PrismaAgentUnitOfWork } from '../adapters/prisma/prisma-agent-unit-of-work';
import { PrismaCommissionRepository } from '../adapters/prisma/prisma-commission.repository';
import { PrismaReferralAttributionRepository } from '../adapters/prisma/prisma-referral-attribution.repository';
import { PrismaReferralCodeRepository } from '../adapters/prisma/prisma-referral-code.repository';
import { AgentCommissionApprovalService } from '../commission/agent-commission-approval.service';
import { AgentPiiSealer } from '../crypto/agent-pii-sealer';
import { AgentPayoutService } from '../payout/agent-payout.service';
import type { AgentSecretSealer } from '../ports/agent-secret-sealer.port';
import { AgentAdminCommissionService } from './agent-admin-commission.service';
import { AgentAdminPayoutService } from './agent-admin-payout.service';
import { AgentAdminReferralService } from './agent-admin-referral.service';
import { AgentAdminService } from './agent-admin.service';

export function piiUnavailable(): ServiceUnavailableException {
  return new ServiceUnavailableException({
    statusCode: 503,
    error: 'Service Unavailable',
    code: 'AGENT_PROGRAM_UNAVAILABLE',
    message: 'Sealed agent data cannot be read yet.',
  });
}

const UNAVAILABLE_SEALER: AgentSecretSealer = {
  seal: () => {
    throw piiUnavailable();
  },
  open: () => {
    throw piiUnavailable();
  },
};

/** Holder of the admin services (an injectable token for the controllers). */
export class AgentAdminRestDeps {
  constructor(
    readonly admin: AgentAdminService,
    readonly referrals: AgentAdminReferralService,
    readonly commissions: AgentAdminCommissionService,
    readonly payouts: AgentAdminPayoutService,
  ) {}
}

export function buildAgentAdminRest(deps: {
  prisma: PrismaClient;
  adminAudit: AdminAuditService;
  hashing: IdentifierHashService;
  platformSettings: PlatformSettingsService;
  env: Record<string, string | undefined>;
  logger?: Pick<Logger, 'warn'>;
}): AgentAdminRestDeps {
  const { prisma } = deps;
  const clock = new SystemClock();
  const uow = new PrismaAgentUnitOfWork(prisma);
  const agents = new PrismaAgentRepository(prisma);
  const codes = new PrismaReferralCodeRepository(prisma);
  const payoutDetails = new PrismaAgentPayoutDetailsRepository(prisma);
  const attributions = new PrismaReferralAttributionRepository(prisma);
  const commissions = new PrismaCommissionRepository(prisma);
  const ledger = new PrismaAgentLedgerRepository(prisma);
  const payouts = new PrismaAgentPayoutRepository(prisma);
  const permission = new AdminPermissionAdapter(prisma);
  const audit = new AdminAuditAdapter(prisma, deps.adminAudit);
  const settings = {
    getMany: (keys: readonly string[]) => deps.platformSettings.getMany(keys),
  };
  const key = parseSealingKey(
    deps.env.AGENT_PII_ENCRYPTION_KEY,
    'AGENT_PII_ENCRYPTION_KEY',
  );
  if (!key) {
    (deps.logger ?? new Logger('AgentAdmin')).warn(
      'AGENT_PII_ENCRYPTION_KEY is not set: revealing agent PAN, phone and payout details answers 503.',
    );
  }
  const sealer = key ? new AgentPiiSealer(key) : UNAVAILABLE_SEALER;

  const approval = new AgentCommissionApprovalService({
    uow,
    agents,
    attributions,
    commissions,
    ledger,
    settings,
    audit,
    clock,
    profiles: NO_MEMBER_PROFILE_VERIFICATION,
  });
  const payoutService = new AgentPayoutService({
    uow,
    agents,
    payoutDetails,
    commissions,
    ledger,
    payouts,
    settings,
    audit,
    clock,
  });
  return new AgentAdminRestDeps(
    new AgentAdminService({
      uow,
      agents,
      codes,
      payoutDetails,
      attributions,
      permission,
      audit,
      clock,
      sealer,
      hasher: new IdentifierHashAdapter(deps.hashing),
      history: new PrismaAgentStatusHistory(prisma),
    }),
    new AgentAdminReferralService({
      uow,
      agents,
      attributions,
      permission,
      audit,
    }),
    new AgentAdminCommissionService({
      uow,
      agents,
      commissions,
      ledger,
      approval,
      permission,
      audit,
      clock,
    }),
    new AgentAdminPayoutService({
      uow,
      agents,
      codes,
      payoutDetails,
      commissions,
      payouts,
      payoutService,
      permission,
      audit,
      sealer,
    }),
  );
}
