/**
 * The signed-in agent's routes (docs/agent-program/agent-api.openapi.yaml):
 * POST /agent/application, GET /agent/me, PATCH /agent/me/payout-details,
 * GET /agent/config, GET /agent/referral-links, GET /agent/referrals and
 * GET /agent/referrals/:id.
 *
 * Every route needs an agent access token (AgentAccessGuard); only the
 * application and GET /agent/me also accept an APPLICANT token. What each
 * agent STATUS may do is the services' rule (`AgentMeService.assertCan`),
 * and every read is scoped to the caller's own agent there.
 */
import {
  Body,
  Controller,
  Get,
  HttpCode,
  Inject,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { validationFailed } from '@app/common';
import type { AgentPayoutDetailsSummary } from '../agent/agent-me.service';
import type { AgentProfile } from '../agent/agent-profile-builder';
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import type { AgentSession } from '../auth/agent-session-issuer';
import type { AgentConfig } from '../config/agent-config.service';
import type { AgentReferralView } from '../referral/agent-referral-view';
import type {
  AgentReferralLink,
  AgentReferralsPage,
} from '../referral/agent-referral.service';
import { AgentErrorsFilter } from './agent-errors.filter';
import {
  AcceptVersionGuard,
  AgentAccessGuard,
  AgentClaims,
  AgentScopes,
} from './agent-http';
import {
  AGENT_PROGRAM,
  agentProgramUnavailable,
  type AgentProgram,
} from './agent-program';
import {
  ApplicationDto,
  PayoutDetailsDto,
  ReferralsQueryDto,
} from './agent-program.dto';

@ApiTags('Agent')
@Controller('agent')
@UseGuards(AcceptVersionGuard, AgentAccessGuard)
@UseFilters(AgentErrorsFilter)
export class AgentController {
  constructor(@Inject(AGENT_PROGRAM) private readonly program: AgentProgram) {}

  @Post('application')
  @HttpCode(201)
  @AgentScopes('APPLICANT', 'AGENT')
  @ApiOperation({ summary: 'Apply to become an agent' })
  apply(
    @AgentClaims() claims: AgentAccessClaims,
    @Body() body: ApplicationDto,
  ): Promise<AgentSession> {
    this.requirePiiSealing();
    return this.program.application.submit(claims, body);
  }

  @Get('me')
  @AgentScopes('APPLICANT', 'AGENT')
  @ApiOperation({ summary: "The signed-in agent's profile and status" })
  me(@AgentClaims() claims: AgentAccessClaims): Promise<AgentProfile> {
    return this.program.me.getProfile(claims);
  }

  @Patch('me/payout-details')
  @ApiOperation({ summary: 'Set or change where commission is paid' })
  updatePayoutDetails(
    @AgentClaims() claims: AgentAccessClaims,
    @Body() body: PayoutDetailsDto,
  ): Promise<AgentPayoutDetailsSummary> {
    this.requirePiiSealing();
    return this.program.me.updatePayoutDetails(claims, body);
  }

  @Get('config')
  @ApiOperation({ summary: 'Labels, share messages and displayed settings' })
  config(): Promise<AgentConfig> {
    return this.program.config.getConfig();
  }

  @Get('referral-links')
  @ApiOperation({ summary: "The agent's codes, links and QR payloads" })
  referralLinks(
    @AgentClaims() claims: AgentAccessClaims,
  ): Promise<{ items: AgentReferralLink[] }> {
    return this.program.referrals.getLinks(claims);
  }

  @Get('referrals')
  @ApiOperation({ summary: 'Members this agent referred' })
  referrals(
    @AgentClaims() claims: AgentAccessClaims,
    @Query() query: ReferralsQueryDto,
  ): Promise<AgentReferralsPage> {
    return this.program.referrals.listReferrals(claims, query);
  }

  @Get('referrals/:id')
  @ApiOperation({ summary: 'One referred member' })
  referral(
    @AgentClaims() claims: AgentAccessClaims,
    @Param('id', new ParseUUIDPipe({ exceptionFactory: validationFailed }))
    id: string,
  ): Promise<AgentReferralView> {
    return this.program.referrals.getReferral(claims, id);
  }

  private requirePiiSealing(): void {
    if (!this.program.piiSealing) throw agentProgramUnavailable();
  }
}
