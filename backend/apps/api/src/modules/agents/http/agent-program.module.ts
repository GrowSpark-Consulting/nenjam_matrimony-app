/**
 * The agent-facing and member referral routes, and the referral quote for
 * the checkout. Registered ONLY when AGENT_PROGRAM_ENABLED is exactly `true`
 * (see `agentProgramEnabled` and `AgentsModule`): with the flag off nothing
 * here exists, the routes answer 404, and nothing is provided under
 * AGENT_REFERRAL_QUOTE, so the checkout charges the list price.
 *
 * Global so the checkout (SubscriptionModule, which cannot import this
 * module: AgentsModule → AdminModule → SubscriptionModule) can inject
 * AGENT_REFERRAL_QUOTE.
 */
import { Global, Module } from '@nestjs/common';
import { PrismaService } from '@app/database';
import { AdminModule } from '../../admin/admin.module';
import { AdminAuditService } from '../../admin/services/admin-audit.service';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { OtpService } from '../../platform/otp/otp.service';
import { PlatformModule } from '../../platform/platform.module';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import {
  AGENT_REFERRAL_QUOTE,
  type AgentReferralQuote,
} from '../agent-referral-quote.token';
import { AgentAuthController } from './agent-auth.controller';
import { AgentController } from './agent.controller';
import { AgentAccessGuard } from './agent-http';
import {
  AGENT_PROGRAM,
  buildAgentProgram,
  type AgentProgram,
} from './agent-program';
import { MemberReferralController } from './member-referral.controller';

/** The flag: on only when exactly `true` (any case), like the other flags. */
export function agentProgramEnabled(
  env: Record<string, string | undefined>,
): boolean {
  return env.AGENT_PROGRAM_ENABLED?.trim().toLowerCase() === 'true';
}

@Global()
@Module({
  imports: [AdminModule, PlatformModule],
  controllers: [AgentAuthController, AgentController, MemberReferralController],
  providers: [
    {
      provide: AGENT_PROGRAM,
      inject: [
        PrismaService,
        PlatformSettingsService,
        OtpService,
        IdentifierHashService,
        AdminAuditService,
      ],
      useFactory: (
        prisma: PrismaService,
        platformSettings: PlatformSettingsService,
        otp: OtpService,
        hashing: IdentifierHashService,
        adminAudit: AdminAuditService,
      ): AgentProgram =>
        buildAgentProgram({
          prisma,
          platformSettings,
          otp,
          hashing,
          adminAudit,
          env: process.env,
        }),
    },
    {
      provide: AGENT_REFERRAL_QUOTE,
      inject: [AGENT_PROGRAM],
      useFactory: (program: AgentProgram): AgentReferralQuote => program.quote,
    },
    AgentAccessGuard,
  ],
  exports: [AGENT_REFERRAL_QUOTE],
})
export class AgentProgramModule {}
