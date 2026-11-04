/**
 * Admin money routes (docs/agent-program/agent-admin-api.openapi.yaml):
 * referral correction, commissions (list, approve, cancel, override) and
 * payouts (list, create, one, mark-paid, cancel). Every route declares its
 * permission; payout create, mark-paid and cancel need payout.execute with a
 * fresh step-up (AdminGuard, and the service again). A payout's destination
 * is included only with payout.execute AND a fresh step-up (the service);
 * otherwise it is left out, 200, and no audit row.
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
  Res,
  UseFilters,
} from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import type { Response } from 'express';
import { validationFailed } from '@app/common';
import {
  AdminContext,
  type AdminRequestContext,
  type AuthenticatedAdmin,
  CurrentAdmin,
} from '../../admin/auth/admin-request';
import {
  AdminController,
  RequirePermissions,
} from '../../admin/auth/admin-route.decorators';
import { restActorOf } from './agent-admin-actions.controller';
import { AgentAdminErrorsFilter } from './agent-admin-errors.filter';
import { AgentAdminRestDeps } from './agent-admin-rest.wiring';
import {
  AdminCommissionOverrideDto,
  AdminCommissionsQueryDto,
  AdminPayableQueryDto,
  AdminPayoutCreateDto,
  AdminPayoutMarkPaidDto,
  AdminPayoutsQueryDto,
  AdminReferralCorrectDto,
} from './agent-admin-rest.dto';
import type { ReferralCorrection } from './agent-admin-referral.service';
import { AdminAgentReasonDto } from './agent-admin.dto';

const idPipe = new ParseUUIDPipe({ exceptionFactory: validationFailed });

@AdminController('admin')
@UseFilters(AgentAdminErrorsFilter)
export class AgentAdminMoneyController {
  constructor(private readonly rest: AgentAdminRestDeps) {}

  @Post('referrals/:id/correct')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('attribution.override')
  @ApiOperation({ summary: 'Correct an attribution (with a recorded reason)' })
  correct(
    @Param('id', idPipe) id: string,
    @Body() body: AdminReferralCorrectDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    const input: ReferralCorrection =
      body.action === 'REASSIGN_AGENT'
        ? {
            action: body.action,
            agentId: body.agentId as string,
            reason: body.reason,
          }
        : { action: body.action, reason: body.reason };
    return this.rest.referrals.correct(restActorOf(admin, context), id, input);
  }

  @Get('commissions')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'List commissions' })
  commissions(
    @Query() query: AdminCommissionsQueryDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.rest.commissions.list(restActorOf(admin, context), query);
  }

  @Post('commissions/:id/approve')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('commission.approve')
  @ApiOperation({ summary: 'Approve a commission' })
  approveCommission(
    @Param('id', idPipe) id: string,
    @Body() body: AdminAgentReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.rest.commissions.approve(
      restActorOf(admin, context),
      id,
      body.reason,
    );
  }

  @Post('commissions/:id/cancel')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('commission.cancel')
  @ApiOperation({ summary: 'Cancel a commission' })
  cancelCommission(
    @Param('id', idPipe) id: string,
    @Body() body: AdminAgentReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.rest.commissions.cancel(
      restActorOf(admin, context),
      id,
      body.reason,
    );
  }

  @Post('commissions/:id/override')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('commission.override')
  @ApiOperation({ summary: "Override a commission's amount" })
  overrideCommission(
    @Param('id', idPipe) id: string,
    @Body() body: AdminCommissionOverrideDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.rest.commissions.override(
      restActorOf(admin, context),
      id,
      body.amountPaise,
      body.reason,
    );
  }

  @Get('payouts')
  @RequirePermissions('payout.view')
  @ApiOperation({ summary: 'List payouts' })
  payouts(
    @Query() query: AdminPayoutsQueryDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.rest.payouts.list(restActorOf(admin, context), query);
  }

  @Post('payouts')
  @RequirePermissions('payout.execute')
  @ApiOperation({
    summary: 'Create a payout (201 new, 200 if it already existed)',
  })
  async createPayout(
    @Body() body: AdminPayoutCreateDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
    @Res({ passthrough: true }) response: Response,
  ) {
    const { payout, created } = await this.rest.payouts.create(
      restActorOf(admin, context),
      body,
    );
    response.status(created ? HttpStatus.CREATED : HttpStatus.OK);
    return payout;
  }

  // Before 'payouts/:id', so "payable" is not read as an id.
  @Get('payouts/payable')
  @RequirePermissions('payout.view')
  @ApiOperation({ summary: 'Agents with a payable balance for a period' })
  payable(
    @Query() query: AdminPayableQueryDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.rest.payouts.listPayable(restActorOf(admin, context), query);
  }

  @Get('payouts/:id')
  @RequirePermissions('payout.view')
  @ApiOperation({ summary: 'One payout (destination only with step-up)' })
  payout(
    @Param('id', idPipe) id: string,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.rest.payouts.get(restActorOf(admin, context), id);
  }

  @Post('payouts/:id/mark-paid')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('payout.execute')
  @ApiOperation({ summary: 'Record that a payout was paid' })
  markPaid(
    @Param('id', idPipe) id: string,
    @Body() body: AdminPayoutMarkPaidDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.rest.payouts.markPaid(restActorOf(admin, context), id, {
      reference: body.reference,
      paidAt: new Date(body.paidAt),
      reason: body.reason,
    });
  }

  @Post('payouts/:id/cancel')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('payout.execute')
  @ApiOperation({ summary: 'Cancel a created payout' })
  cancelPayout(
    @Param('id', idPipe) id: string,
    @Body() body: AdminAgentReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.rest.payouts.cancel(
      restActorOf(admin, context),
      id,
      body.reason,
    );
  }
}
