/**
 * The agent-facing and member referral routes. Registered ONLY when
 * AGENT_PROGRAM_ENABLED is exactly `true` (see `agentProgramEnabled` and
 * `AgentsModule`): with the flag off nothing here exists and the routes
 * answer 404. The checkout's referral quote is NOT here: it is provided by
 * AgentReferralQuoteModule whatever the flag.
 */
import { Module } from '@nestjs/common';
import { PrismaService } from '@app/database';
import { AdminModule } from '../../admin/admin.module';
import { AdminAuditService } from '../../admin/services/admin-audit.service';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { OtpService } from '../../platform/otp/otp.service';
import { PlatformModule } from '../../platform/platform.module';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
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
    AgentAccessGuard,
  ],
})
export class AgentProgramModule {}
