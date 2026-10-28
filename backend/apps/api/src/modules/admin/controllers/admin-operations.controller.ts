import {
  Body,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
} from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import { SubscriptionLifecycleService } from '../../subscription/services/subscription-lifecycle.service';
import { type AuthenticatedAdmin, CurrentAdmin } from '../auth/admin-request';
import {
  AdminController,
  RequirePermissions,
} from '../auth/admin-route.decorators';
import {
  AdminReasonDto,
  AuditLogQueryDto,
  ExtendSubscriptionDto,
  SubscriptionQueryDto,
} from '../dto/admin-membership.dto';
import { AdminQueriesService } from '../services/admin-queries.service';

/**
 * Member subscriptions. Lookup by exact identifier only; contact details are
 * masked. Actions are the lifecycle service's — permission-checked and
 * audited inside its own transaction. Complimentary grants and extensions
 * over 30 days need a second approver (Admin Architecture v3) and are not
 * offered until that workflow exists.
 */
@AdminController('admin/subscriptions')
export class AdminSubscriptionsController {
  constructor(
    private readonly queries: AdminQueriesService,
    private readonly lifecycle: SubscriptionLifecycleService,
  ) {}

  @Get()
  @RequirePermissions('subscription.view')
  @ApiOperation({ summary: 'Search subscriptions (cursor-paginated)' })
  list(@Query() query: SubscriptionQueryDto) {
    return this.queries.subscriptions(query);
  }

  @Get(':id')
  @RequirePermissions('subscription.view')
  @ApiOperation({ summary: 'A subscription with its events and payments' })
  get(@Param('id', ParseUUIDPipe) id: string) {
    return this.queries.subscription(id);
  }

  @Post(':id/extend')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('subscription.extend')
  @ApiOperation({ summary: 'Add up to 30 days to an active subscription' })
  async extend(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: ExtendSubscriptionDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
  ) {
    await this.lifecycle.extend({
      subscriptionId: id,
      days: body.days,
      actorId: admin.userId,
      reason: body.reason,
    });
    return this.queries.subscription(id);
  }

  @Post(':id/revoke')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('subscription.cancel')
  @ApiOperation({ summary: 'End an active subscription now (no refund)' })
  async revoke(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: AdminReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
  ) {
    await this.lifecycle.revoke({
      subscriptionId: id,
      actorId: admin.userId,
      reason: body.reason,
    });
    return this.queries.subscription(id);
  }
}

@AdminController('admin/audit-logs')
export class AdminAuditLogsController {
  constructor(private readonly queries: AdminQueriesService) {}

  @Get()
  @RequirePermissions('audit.view')
  @ApiOperation({ summary: 'Search the audit log (read-only, newest first)' })
  list(@Query() query: AuditLogQueryDto) {
    return this.queries.auditLogs({
      ...query,
      from: query.from ? new Date(query.from) : undefined,
      to: query.to ? new Date(query.to) : undefined,
    });
  }
}

@AdminController('admin/overview')
export class AdminOverviewController {
  constructor(private readonly queries: AdminQueriesService) {}

  @Get()
  @RequirePermissions('dashboard.view')
  @ApiOperation({
    summary: 'Counts for the overview page (revenue only with finance.view)',
  })
  get(@CurrentAdmin() admin: AuthenticatedAdmin) {
    return this.queries.overview(admin.permissions);
  }
}

@AdminController('admin/roles')
export class AdminRolesController {
  constructor(private readonly queries: AdminQueriesService) {}

  @Get()
  @RequirePermissions('rbac.manage')
  @ApiOperation({ summary: 'Roles, their permissions and admins (read-only)' })
  list() {
    return this.queries.roles();
  }
}
