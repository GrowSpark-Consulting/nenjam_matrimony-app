/**
 * `/admin/agents` (PR A): summary, list, detail, approve, reject. Thin: every
 * route declares its permission for the admin guard, and the service checks
 * it again inside the transaction that makes the change.
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
} from '../../admin/auth/admin-request';
import {
  AdminController,
  RequirePermissions,
} from '../../admin/auth/admin-route.decorators';
import {
  AgentAdminAgentsService,
  type AdminActor,
} from './agent-admin-agents.service';
import { AgentAdminErrorsFilter } from './agent-admin-errors.filter';
import { AdminAgentReasonDto, AdminAgentsQueryDto } from './agent-admin.dto';

const idPipe = new ParseUUIDPipe({ exceptionFactory: validationFailed });

const actorOf = (
  admin: AuthenticatedAdmin,
  context: AdminRequestContext,
): AdminActor => ({ userId: admin.userId, context });

@AdminController('admin/agents')
@UseFilters(AgentAdminErrorsFilter)
export class AgentAdminController {
  constructor(private readonly agents: AgentAdminAgentsService) {}

  // Before ':id', so "summary" is not read as an id.
  @Get('summary')
  @RequirePermissions('agent.view')
  @ApiOperation({ summary: 'Counts for the agents page' })
  summary(
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.agents.summary(actorOf(admin, context));
  }

  @Get()
  @RequirePermissions('agent.view')
  @ApiOperation({ summary: 'List agents (cursor-paginated, newest first)' })
  list(
    @Query() query: AdminAgentsQueryDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.agents.list(actorOf(admin, context), query);
  }

  @Get(':id')
  @RequirePermissions('agent.view')
  @ApiOperation({ summary: 'One agent (masked)' })
  get(
    @Param('id', idPipe) id: string,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.agents.get(actorOf(admin, context), id);
  }

  @Post(':id/approve')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('agent.approve')
  @ApiOperation({ summary: 'Approve an application (issues the first code)' })
  approve(
    @Param('id', idPipe) id: string,
    @Body() body: AdminAgentReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.agents.approve(actorOf(admin, context), id, body.reason);
  }

  @Post(':id/reject')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('agent.approve')
  @ApiOperation({
    summary: 'Reject an application (the reason is shown to the applicant)',
  })
  reject(
    @Param('id', idPipe) id: string,
    @Body() body: AdminAgentReasonDto,
    @CurrentAdmin() admin: AuthenticatedAdmin,
    @AdminContext() context: AdminRequestContext,
  ) {
    return this.agents.reject(actorOf(admin, context), id, body.reason);
  }
}
