/**
 * The remaining /admin/agents/:id routes
 * (docs/agent-program/agent-admin-api.openapi.yaml): pause, resume,
 * terminate, codes/replace, payout-details/verify, pan/verify, reveal and the
 * agent's referrals. Every route declares its permission (AdminRouteCheck);
 * reveal also needs a fresh step-up, which AdminGuard enforces for
 * agent.pii.reveal and the service checks again. Audit rows are written in
 * the same transaction, with the request context.
 */
import {
  Body,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseFilters,
} from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import { validationFailed } from '@app/common';
import {
  AdminContext,
  type AdminRequestContext,
  type AuthenticatedAdmin,
  CurrentAdmin,
  hasFreshStepUp,
} from '../../admin/auth/admin-request';
import {
  AdminController,
  RequirePermissions,
} from '../../admin/auth/admin-route.decorators';
import { AgentAdminAgentsService } from './agent-admin-agents.service';
import { AgentAdminErrorsFilter } from './agent-admin-errors.filter';
import { AgentAdminReferralService } from './agent-admin-referral.service';
import { AgentAdminRestDeps } from './agent-admin-rest.wiring';
import {
  AdminAgentReferralsQueryDto,
  AdminRevealDto,
} from './agent-admin-rest.dto';
import type { AdminActor } from './agent-admin-support';
import { AgentAdminService } from './agent-admin.service';
import { AdminAgentReasonDto } from './agent-admin.dto';

const idPipe = new ParseUUIDPipe({ exceptionFactory: validationFailed });

/** The actor the money and admin services take. */
export function restActorOf(
  admin: AuthenticatedAdmin,
  context: AdminRequestContext,
): AdminActor {
  return {
    userId: admin.userId,
    stepUpFresh: hasFreshStepUp(admin),
    context,
  };
}

@AdminController('admin/agents')
@UseFilters(AgentAdminErrorsFilter)
export class AgentAdminActionsController {
  private readonly admin: AgentAdminService;
  private readonly referrals: AgentAdminReferralService;

  constructor(
    private readonly agents: AgentAdminAgentsService,
    rest: AgentAdminRestDeps,
  ) {
    this.admin = rest.admin;
    this.referrals = rest.referrals;
  }

  @Post(':id/pause')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('agent.manage')
  @ApiOperation({ summary: 'Pause an agent (ACTIVE -> SUSPENDED)' })
  pause(
    @Param('id', idPipe) id: string,
    @Body() body: AdminAgentReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.agents.pause(
      { userId: admin.userId, context },
      id,
      body.reason,
    );
  }

  @Post(':id/resume')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('agent.manage')
  @ApiOperation({ summary: 'Resume a paused agent (SUSPENDED -> ACTIVE)' })
  resume(
    @Param('id', idPipe) id: string,
    @Body() body: AdminAgentReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.agents.resume(
      { userId: admin.userId, context },
      id,
      body.reason,
    );
  }

  @Post(':id/terminate')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('agent.manage')
  @ApiOperation({ summary: 'Terminate an agent (final)' })
  terminate(
    @Param('id', idPipe) id: string,
    @Body() body: AdminAgentReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.agents.terminate(
      { userId: admin.userId, context },
      id,
      body.reason,
    );
  }

  @Post(':id/codes/replace')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('agent.manage')
  @ApiOperation({ summary: "Replace the agent's primary referral code" })
  replaceCode(
    @Param('id', idPipe) id: string,
    @Body() body: AdminAgentReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.admin.replaceCode(restActorOf(admin, context), id, body.reason);
  }

  @Post(':id/payout-details/verify')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('agent.payout_details.verify')
  @ApiOperation({ summary: "Mark the agent's current payout details verified" })
  verifyPayoutDetails(
    @Param('id', idPipe) id: string,
    @Body() body: AdminAgentReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.admin.verifyPayoutDetails(
      restActorOf(admin, context),
      id,
      body.reason,
    );
  }

  @Post(':id/pan/verify')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('agent.payout_details.verify')
  @ApiOperation({ summary: "Mark the agent's PAN verified" })
  verifyPan(
    @Param('id', idPipe) id: string,
    @Body() body: AdminAgentReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.admin.verifyPan(restActorOf(admin, context), id, body.reason);
  }

  @Post(':id/reveal')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('agent.pii.reveal')
  @ApiOperation({ summary: 'Reveal sealed values once (step-up, audited)' })
  reveal(
    @Param('id', idPipe) id: string,
    @Body() body: AdminRevealDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.admin.reveal(
      restActorOf(admin, context),
      id,
      body.fields,
      body.reason,
    );
  }

  @Get(':id/referrals')
  @RequirePermissions('attribution.view')
  @ApiOperation({ summary: "The agent's referrals (with review state)" })
  referralsOf(
    @Param('id', idPipe) id: string,
    @Query() query: AdminAgentReferralsQueryDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.referrals.list(restActorOf(admin, context), id, query);
  }
}
