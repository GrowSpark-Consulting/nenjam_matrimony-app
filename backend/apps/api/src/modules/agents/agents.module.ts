/**
 * The agent program, as far as it is wired today: the admin routes for
 * agents (summary, list, detail, approve, reject).
 *
 * Built only from what is on main: the Prisma adapters for the Phase 1
 * tables, the permission and audit ports over admin RBAC and
 * `AdminAuditService` (both on the request's transaction, through our unit
 * of work), and the identifier hasher over `IdentifierHashService`.
 *
 * The agent-facing and member referral routes live in `AgentProgramModule`
 * (`http/`), imported only when AGENT_PROGRAM_ENABLED=true.
 */
import { Module } from '@nestjs/common';
import { ConditionalModule } from '@nestjs/config';
import { PrismaService } from '@app/database';
import { AdminModule } from '../admin/admin.module';
import { AdminAuditService } from '../admin/services/admin-audit.service';
import { IdentifierHashService } from '../platform/identifier-hash.service';
import { PlatformModule } from '../platform/platform.module';
import {
  AdminAuditAdapter,
  AdminPermissionAdapter,
  IdentifierHashAdapter,
  SystemClock,
} from './adapters/admin/agent-admin-platform.adapters';
import { AgentSettingValidators } from './adapters/platform/agent-platform.adapters';
import { PrismaAgentAdminRead } from './adapters/prisma/prisma-agent-admin-read';
import { PrismaAgentPayoutDetailsRepository } from './adapters/prisma/prisma-agent-payout-details.repository';
import { PrismaAgentRepository } from './adapters/prisma/prisma-agent.repository';
import { PrismaAgentUnitOfWork } from './adapters/prisma/prisma-agent-unit-of-work';
import { PrismaReferralAttributionRepository } from './adapters/prisma/prisma-referral-attribution.repository';
import { PrismaReferralCodeRepository } from './adapters/prisma/prisma-referral-code.repository';
import { AgentAdminAgentsService } from './admin/agent-admin-agents.service';
import { AgentAdminController } from './admin/agent-admin.controller';
import {
  AgentProgramModule,
  agentProgramEnabled,
} from './http/agent-program.module';

@Module({
  imports: [
    AdminModule,
    PlatformModule,
    // The agent-facing and member referral routes: registered only when
    // AGENT_PROGRAM_ENABLED=true; otherwise they do not exist (404).
    ConditionalModule.registerWhen(AgentProgramModule, agentProgramEnabled),
  ],
  controllers: [AgentAdminController],
  providers: [
    // Refuses a bad agent-program setting when an admin enters it.
    AgentSettingValidators,
    {
      provide: AgentAdminAgentsService,
      inject: [PrismaService, AdminAuditService, IdentifierHashService],
      useFactory: (
        prisma: PrismaService,
        audit: AdminAuditService,
        hashing: IdentifierHashService,
      ) =>
        new AgentAdminAgentsService({
          // The transaction options are the client's own (PrismaService).
          uow: new PrismaAgentUnitOfWork(prisma),
          agents: new PrismaAgentRepository(prisma),
          codes: new PrismaReferralCodeRepository(prisma),
          payoutDetails: new PrismaAgentPayoutDetailsRepository(prisma),
          attributions: new PrismaReferralAttributionRepository(prisma),
          read: new PrismaAgentAdminRead(prisma),
          permission: new AdminPermissionAdapter(prisma),
          audit: new AdminAuditAdapter(prisma, audit),
          hasher: new IdentifierHashAdapter(hashing),
          clock: new SystemClock(),
        }),
    },
  ],
})
export class AgentsModule {}
