/**
 * The agent-facing and member referral routes. Registered ONLY when
 * AGENT_PROGRAM_ENABLED is exactly `true` (see `agentProgramEnabled` and
 * `AgentsModule`): with the flag off nothing here exists and the routes
 * answer 404. The checkout's referral quote is NOT here: it is provided by
 * AgentReferralQuoteModule whatever the flag.
 */
import { Module } from '@nestjs/common';
import { AppConfigModule, AppConfigService } from '@app/config';
import { PrismaService } from '@app/database';
import { FirebaseService } from '@app/firebase';
import { LocationService } from '../../reference-data/services/location.service';
import { ReligionService } from '../../reference-data/services/religion.service';
import { AdminModule } from '../../admin/admin.module';
import { AdminAuditService } from '../../admin/services/admin-audit.service';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { OtpService } from '../../platform/otp/otp.service';
import { PlatformModule } from '../../platform/platform.module';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import { AgentAuthController } from './agent-auth.controller';
import { AgentController } from './agent.controller';
import { AgentAccessGuard, ClientInviteGuard } from './agent-http';
import { AgentClientsController } from './agent-clients.controller';
import { ClientInvitesController } from './client-invites.controller';
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
  // AppConfigModule is not global: the client invitations read
  // AGENT_OTP_DUMMY_* from it, exactly as the OTP service does.
  imports: [AdminModule, PlatformModule, AppConfigModule],
  controllers: [
    AgentAuthController,
    AgentController,
    MemberReferralController,
    AgentClientsController,
    ClientInvitesController,
  ],
  providers: [
    {
      provide: AGENT_PROGRAM,
      inject: [
        PrismaService,
        PlatformSettingsService,
        OtpService,
        IdentifierHashService,
        AdminAuditService,
        FirebaseService,
        AppConfigService,
        // The reference-data module is global.
        LocationService,
        ReligionService,
      ],
      useFactory: (
        prisma: PrismaService,
        platformSettings: PlatformSettingsService,
        otp: OtpService,
        hashing: IdentifierHashService,
        adminAudit: AdminAuditService,
        firebase: FirebaseService,
        config: AppConfigService,
        locations: LocationService,
        religions: ReligionService,
      ): AgentProgram =>
        buildAgentProgram({
          prisma,
          platformSettings,
          otp,
          hashing,
          adminAudit,
          firebase,
          agentOtp: config.agentOtp,
          locations,
          religions,
          env: process.env,
        }),
    },
    AgentAccessGuard,
    ClientInviteGuard,
  ],
})
export class AgentProgramModule {}
