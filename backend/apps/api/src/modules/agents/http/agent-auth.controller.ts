/**
 * Agent sign-in (docs/agent-program/agent-api.openapi.yaml, "Agent auth"):
 * POST /agent/auth/otp/request, /otp/verify, /refresh, /logout.
 *
 * Request and verify need both the token secret and the sealing key (verify
 * seals an applicant's phone), and refuse with 503 BEFORE an OTP is sent or
 * used up when either is missing. Refresh needs the token secret only.
 */
import {
  Body,
  Controller,
  HttpCode,
  Inject,
  Post,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import type {
  AgentApplicantSession,
  AgentSession,
} from '../auth/agent-session-issuer';
import type { AgentOtpStartResult } from '../auth/agent-sign-in.service';
import { AgentErrorsFilter } from './agent-errors.filter';
import {
  AcceptVersionGuard,
  AgentAccessGuard,
  AgentClaims,
} from './agent-http';
import {
  AGENT_PROGRAM,
  agentProgramUnavailable,
  type AgentProgram,
} from './agent-program';
import {
  LogoutDto,
  OtpRequestDto,
  OtpVerifyDto,
  RefreshDto,
} from './agent-program.dto';

@ApiTags('Agent auth')
@Controller('agent/auth')
@UseGuards(AcceptVersionGuard)
@UseFilters(AgentErrorsFilter)
export class AgentAuthController {
  constructor(@Inject(AGENT_PROGRAM) private readonly program: AgentProgram) {}

  @Post('otp/request')
  @HttpCode(200)
  @ApiOperation({ summary: 'Send a sign-in OTP to an agent phone' })
  request(@Body() body: OtpRequestDto): Promise<AgentOtpStartResult> {
    this.requireSignIn();
    return this.program.signIn.start(body.phone);
  }

  @Post('otp/verify')
  @HttpCode(200)
  @ApiOperation({ summary: 'Verify the OTP and get agent tokens' })
  verify(
    @Body() body: OtpVerifyDto,
  ): Promise<AgentSession | AgentApplicantSession> {
    this.requireSignIn();
    return this.program.signIn.verify(body.challengeId, body.code);
  }

  @Post('refresh')
  @HttpCode(200)
  @ApiOperation({ summary: 'Exchange a refresh token for a new pair' })
  refresh(@Body() body: RefreshDto): Promise<AgentSession> {
    if (this.program.tokens === null) throw agentProgramUnavailable();
    return this.program.signIn.refresh(body.refreshToken);
  }

  @Post('logout')
  @HttpCode(204)
  @UseGuards(AgentAccessGuard)
  @ApiOperation({ summary: "Revoke this session's refresh token" })
  async logout(
    @AgentClaims() claims: AgentAccessClaims,
    @Body() body: LogoutDto,
  ): Promise<void> {
    await this.program.signIn.logout(claims, body.refreshToken);
  }

  private requireSignIn(): void {
    if (this.program.tokens === null || !this.program.piiSealing) {
      throw agentProgramUnavailable();
    }
  }
}
