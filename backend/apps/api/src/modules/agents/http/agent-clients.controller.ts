/**
 * Agent-added clients, the agent's routes (docs/agent-program/agent-api.openapi.yaml,
 * "Clients"): POST/GET /agent/clients, GET/PATCH/DELETE /agent/clients/:id,
 * POST /agent/clients/:id/submit.
 *
 * Agent access token only (AGENT scope; a client token is refused by
 * AgentAccessGuard). The switch (`agent.clients_enabled`), the agent's
 * status and the own-drafts scoping are the service's rules
 * (`AgentClientDraftService`). Every route seals or opens client PII, so
 * each answers 503 while AGENT_PII_ENCRYPTION_KEY is not set.
 */
import {
  Body,
  Controller,
  Delete,
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
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import type { AgentClientsPage } from '../clients/agent-client-draft.service';
import type { ClientDraftView } from '../clients/client-draft-view';
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
  ClientCreateDto,
  ClientsQueryDto,
  ClientUpdateDto,
} from './agent-program.dto';

const draftId = new ParseUUIDPipe({ exceptionFactory: validationFailed });

@ApiTags('Clients')
@Controller('agent/clients')
@UseGuards(AcceptVersionGuard, AgentAccessGuard)
@UseFilters(AgentErrorsFilter)
export class AgentClientsController {
  constructor(@Inject(AGENT_PROGRAM) private readonly program: AgentProgram) {}

  @Post()
  @HttpCode(201)
  @ApiOperation({ summary: 'Add a client (create a DRAFT)' })
  create(
    @AgentClaims() claims: AgentAccessClaims,
    @Body() body: ClientCreateDto,
  ): Promise<ClientDraftView> {
    this.requirePiiSealing();
    return this.program.clients.create(claims, body);
  }

  @Get()
  @ApiOperation({ summary: "The agent's clients, newest first" })
  list(
    @AgentClaims() claims: AgentAccessClaims,
    @Query() query: ClientsQueryDto,
  ): Promise<AgentClientsPage> {
    this.requirePiiSealing();
    return this.program.clients.list(claims, query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'One client draft' })
  get(
    @AgentClaims() claims: AgentAccessClaims,
    @Param('id', draftId) id: string,
  ): Promise<ClientDraftView> {
    this.requirePiiSealing();
    return this.program.clients.get(claims, id);
  }

  @Patch(':id')
  @ApiOperation({ summary: "Edit a DRAFT's details" })
  update(
    @AgentClaims() claims: AgentAccessClaims,
    @Param('id', draftId) id: string,
    @Body() body: ClientUpdateDto,
  ): Promise<ClientDraftView> {
    this.requirePiiSealing();
    return this.program.clients.update(claims, id, body);
  }

  @Delete(':id')
  @HttpCode(204)
  @ApiOperation({ summary: 'Discard a DRAFT' })
  async discard(
    @AgentClaims() claims: AgentAccessClaims,
    @Param('id', draftId) id: string,
  ): Promise<void> {
    this.requirePiiSealing();
    await this.program.clients.discard(claims, id);
  }

  @Post(':id/submit')
  @HttpCode(200)
  @ApiOperation({ summary: 'Submit a DRAFT to the client (locks it)' })
  submit(
    @AgentClaims() claims: AgentAccessClaims,
    @Param('id', draftId) id: string,
  ): Promise<ClientDraftView> {
    this.requirePiiSealing();
    return this.program.clients.submit(claims, id);
  }

  private requirePiiSealing(): void {
    if (!this.program.piiSealing) throw agentProgramUnavailable();
  }
}
