/**
 * The two member-side referral routes (docs/agent-program/agent-api.openapi.yaml,
 * "Member"):
 *  - POST /referrals/codes/validate: no token; attempt-limited per hashed IP
 *    and per code (the limits are settings).
 *  - POST /registration/referral-code: the existing member guard
 *    (FirebaseAuthGuard, unchanged) and the member's own id.
 */
import {
  Body,
  Controller,
  HttpCode,
  Inject,
  Post,
  Req,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import type { AgentAttachResult } from '../referral/agent-referral-code.service';
import { AgentErrorsFilter } from './agent-errors.filter';
import { AcceptVersionGuard } from './agent-http';
import { AGENT_PROGRAM, type AgentProgram } from './agent-program';
import { ReferralCodeDto } from './agent-program.dto';

@ApiTags('Member referrals')
@Controller()
@UseGuards(AcceptVersionGuard)
@UseFilters(AgentErrorsFilter)
export class MemberReferralController {
  constructor(@Inject(AGENT_PROGRAM) private readonly program: AgentProgram) {}

  @Post('referrals/codes/validate')
  @HttpCode(200)
  @ApiOperation({ summary: 'Check a referral code before sign-up' })
  validate(
    @Body() body: ReferralCodeDto,
    @Req() request: Request,
  ): Promise<{ valid: boolean; agentDisplayName: string | null }> {
    return this.program.referralCodes.validateCode(
      body.code,
      this.program.requesterKey(request.ip),
    );
  }

  @Post('registration/referral-code')
  @HttpCode(200)
  @UseGuards(FirebaseAuthGuard)
  @ApiOperation({ summary: 'Attach a referral code after sign-in' })
  attach(
    @CurrentUser('id') memberId: string,
    @Body() body: ReferralCodeDto,
  ): Promise<AgentAttachResult> {
    return this.program.referralCodes.attachCode(memberId, body.code);
  }
}
