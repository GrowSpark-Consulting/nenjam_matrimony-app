import {
  Body,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseEnumPipe,
  Patch,
  Post,
  Put,
  Query,
  ParseUUIDPipe,
} from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import { SubscriptionPlanName } from '../../../../../../libs/database/generated/client';
import { PlanCatalogAdminService } from '../../subscription/services/plan-catalog-admin.service';
import { PlanDraftService } from '../../subscription/services/plan-draft.service';
import {
  AdminContext,
  type AdminRequestContext,
  type AuthenticatedAdmin,
  CurrentAdmin,
} from '../auth/admin-request';
import {
  AdminController,
  RequirePermissions,
} from '../auth/admin-route.decorators';
import {
  AdminReasonDto,
  CreatePlanDraftDto,
  PlanDisplayDto,
  PlanDraftQueryDto,
  PlanStatusDto,
  PublishPlanDraftDto,
  UpdatePlanDraftDto,
} from '../dto/admin-membership.dto';
import { AdminQueriesService } from '../services/admin-queries.service';

const planCode = new ParseEnumPipe(SubscriptionPlanName);

/**
 * The membership catalogue. Reads need plan.view; anything members would see
 * change goes through a draft that a SECOND admin publishes (plan.publish).
 * The only direct changes are display text (plan.edit) and taking a plan on
 * or off sale (plan.publish) — both with a reason.
 */
@AdminController('admin/plans')
export class AdminPlansController {
  constructor(
    private readonly queries: AdminQueriesService,
    private readonly catalogAdmin: PlanCatalogAdminService,
  ) {}

  @Get()
  @RequirePermissions('plan.view')
  @ApiOperation({
    summary: 'Plans, current entitlements, versions, prices, feature registry',
  })
  list() {
    return this.queries.plans();
  }

  @Patch(':code/display')
  @RequirePermissions('plan.edit')
  @ApiOperation({ summary: 'Change a plan’s name, description or order' })
  async display(
    @Param('code', planCode) code: SubscriptionPlanName,
    @Body() body: PlanDisplayDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
  ) {
    await this.catalogAdmin.updatePlanDisplay({
      planCode: code,
      displayName: body.displayName,
      description: body.description,
      displayOrder: body.displayOrder,
      actorId: admin.userId,
      reason: body.reason,
    });
    return this.queries.plans();
  }

  @Post(':code/status')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('plan.publish')
  @ApiOperation({
    summary: 'Put a plan on or off sale (existing subscriptions unaffected)',
  })
  async status(
    @Param('code', planCode) code: SubscriptionPlanName,
    @Body() body: PlanStatusDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
  ) {
    await this.catalogAdmin.setPlanActive({
      planCode: code,
      isActive: body.isActive,
      actorId: admin.userId,
      reason: body.reason,
    });
    return this.queries.plans();
  }
}

@AdminController('admin/plan-drafts')
export class AdminPlanDraftsController {
  constructor(private readonly drafts: PlanDraftService) {}

  @Get()
  @RequirePermissions('plan.view')
  list(@Query() query: PlanDraftQueryDto) {
    return this.drafts.list(query);
  }

  @Post()
  @RequirePermissions('plan.edit')
  @ApiOperation({ summary: 'Start a draft from the plan as it is now' })
  create(
    @Body() body: CreatePlanDraftDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.drafts.create({
      planCode: body.planCode,
      changeNote: body.changeNote,
      actorId: admin.userId,
      context,
    });
  }

  @Get(':id')
  @RequirePermissions('plan.view')
  @ApiOperation({
    summary: 'A draft with its validation and what publishing would change',
  })
  get(@Param('id', ParseUUIDPipe) id: string) {
    return this.drafts.get(id);
  }

  @Put(':id')
  @RequirePermissions('plan.edit')
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: UpdatePlanDraftDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.drafts.update({ id, ...body, actorId: admin.userId, context });
  }

  @Post(':id/submit')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('plan.edit')
  @ApiOperation({
    summary: 'Send for approval (must be valid and change something)',
  })
  submit(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.drafts.submit({ id, actorId: admin.userId, context });
  }

  @Post(':id/publish')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('plan.publish')
  @ApiOperation({
    summary: 'Approve and publish — a different admin from the submitter',
  })
  publish(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: PublishPlanDraftDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.drafts.publish({
      id,
      note: body.note,
      actorId: admin.userId,
      context,
    });
  }

  @Post(':id/reject')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('plan.publish')
  reject(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: AdminReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.drafts.reject({
      id,
      reason: body.reason,
      actorId: admin.userId,
      context,
    });
  }

  @Post(':id/discard')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('plan.edit')
  discard(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: AdminReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.drafts.discard({
      id,
      reason: body.reason,
      actorId: admin.userId,
      context,
    });
  }
}
