/**
 * The agent program, as far as it is wired today: the admin routes for
 * agents (summary, list, detail, approve, reject).
 *
 * Built only from what is on main: the Prisma adapters for the Phase 1
 * tables, the permission and audit ports over admin RBAC and
 * `AdminAuditService` (both on the request's transaction, through our unit
 * of work), and the identifier hasher over `IdentifierHashService`. No agent
 * (member- or agent-facing) route is registered here.
 */
import { Module } from '@nestjs/common';
import { PrismaService } from '@app/database';
import { AdminModule } from '../admin/admin.module';
import { AdminAuditService } from '../admin/services/admin-audit.service';
import { IdentifierHashService } from '../platform/identifier-hash.service';
import { PlatformModule } from '../platform/platform.module';
import { PlatformSettingsService } from '../platform/settings/platform-settings.service';
import { ReferralEventBus } from '../subscription/events/referral-event-bus';
import { SubscriptionModule } from '../subscription/subscription.module';
import {
  AdminAuditAdapter,
  AdminPermissionAdapter,
  IdentifierHashAdapter,
  SystemClock,
} from './adapters/admin/agent-admin-platform.adapters';
import { PrismaAgentAdminRead } from './adapters/prisma/prisma-agent-admin-read';
import { PrismaAgentLedgerRepository } from './adapters/prisma/prisma-agent-ledger.repository';
import { PrismaAgentMemberRead } from './adapters/prisma/prisma-agent-member-read';
import { PrismaAgentPaymentSource } from './adapters/prisma/prisma-agent-payment-source';
import { PrismaCommissionPolicyRepository } from './adapters/prisma/prisma-commission-policy.repository';
import { PrismaCommissionRepository } from './adapters/prisma/prisma-commission.repository';
import { PrismaAgentPayoutDetailsRepository } from './adapters/prisma/prisma-agent-payout-details.repository';
import { PrismaAgentRepository } from './adapters/prisma/prisma-agent.repository';
import { PrismaAgentUnitOfWork } from './adapters/prisma/prisma-agent-unit-of-work';
import { PrismaReferralAttributionRepository } from './adapters/prisma/prisma-referral-attribution.repository';
import { PrismaReferralCodeRepository } from './adapters/prisma/prisma-referral-code.repository';
import { AgentAdminAgentsService } from './admin/agent-admin-agents.service';
import { AgentAdminController } from './admin/agent-admin.controller';
import { AgentAdminActionsController } from './admin/agent-admin-actions.controller';
import { AgentAdminMoneyController } from './admin/agent-admin-money.controller';
import {
  AgentAdminRestDeps,
  buildAgentAdminRest,
} from './admin/agent-admin-rest.wiring';
import { AgentCommissionEventsService } from './commission/agent-commission-events.service';
import { AgentPaymentEventsSubscriber } from './commission/agent-payment-events.subscriber';

@Module({
  imports: [AdminModule, PlatformModule, SubscriptionModule],
  controllers: [
    AgentAdminController,
    AgentAdminActionsController,
    AgentAdminMoneyController,
  ],
  providers: [
    {
      provide: AgentAdminRestDeps,
      inject: [
        PrismaService,
        AdminAuditService,
        IdentifierHashService,
        PlatformSettingsService,
      ],
      useFactory: (
        prisma: PrismaService,
        adminAudit: AdminAuditService,
        hashing: IdentifierHashService,
        platformSettings: PlatformSettingsService,
      ) =>
        buildAgentAdminRest({
          prisma,
          adminAudit,
          hashing,
          platformSettings,
          env: process.env,
        }),
    },
    {
      // The commission handlers, subscribed to the payment events (see the
      // subscriber). Not an agent route: independent of AGENT_PROGRAM_ENABLED.
      provide: AgentPaymentEventsSubscriber,
      inject: [
        PrismaService,
        ReferralEventBus,
        PlatformSettingsService,
        IdentifierHashService,
        AdminAuditService,
      ],
      useFactory: (
        prisma: PrismaService,
        bus: ReferralEventBus,
        settings: PlatformSettingsService,
        hashing: IdentifierHashService,
        audit: AdminAuditService,
      ) => {
        const clock = new SystemClock();
        const hasher = new IdentifierHashAdapter(hashing);
        const policy = new PrismaCommissionPolicyRepository(prisma);
        const events = new AgentCommissionEventsService({
          uow: new PrismaAgentUnitOfWork(prisma),
          agents: new PrismaAgentRepository(prisma),
          attributions: new PrismaReferralAttributionRepository(prisma),
          policy,
          commissions: new PrismaCommissionRepository(prisma),
          ledger: new PrismaAgentLedgerRepository(prisma),
          settings: { getMany: (keys) => settings.getMany(keys) },
          paymentSources: new PrismaAgentPaymentSource(prisma),
          members: new PrismaAgentMemberRead(prisma, hasher, clock),
          hasher,
          audit: new AdminAuditAdapter(prisma, audit),
          clock,
        });
        return new AgentPaymentEventsSubscriber(
          bus,
          events,
          hashing,
          policy,
          clock,
        );
      },
    },
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
