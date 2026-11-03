/**
 * Agent-added clients, the client's routes (docs/agent-program/agent-api.openapi.yaml,
 * "Client invites"): POST /client-invites/otp/request and /otp/verify (no
 * token), GET /client-invites, POST /client-invites/:id/accept and
 * /client-invites/:id/reject (client token, ClientInviteGuard).
 *
 * The client token is NOT an agent token and NOT a Firebase token: its own
 * audience, CLIENT scope only. The switch (`agent.clients_enabled`) and every
 * rule are the service's (`ClientInviteService`). Every route needs the
 * token secret and the PII key (the token's subject is the sealed phone),
 * and answers 503 BEFORE a code is sent or used up when either is missing.
 */
import {
  Body,
  Controller,
  Get,
  HttpCode,
  Inject,
  Param,
  ParseUUIDPipe,
  Post,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { validationFailed } from '@app/common';
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import type {
  ClientAcceptResult,
  ClientCodeSent,
  ClientInviteView,
  ClientSession,
} from '../clients/client-invite.service';
import { AgentErrorsFilter } from './agent-errors.filter';
import {
  AcceptVersionGuard,
  ClientClaims,
  ClientInviteGuard,
} from './agent-http';
import {
  AGENT_PROGRAM,
  agentProgramUnavailable,
  type AgentProgram,
} from './agent-program';
import { ClientOtpVerifyDto, OtpRequestDto } from './agent-program.dto';

const inviteId = new ParseUUIDPipe({ exceptionFactory: validationFailed });

@ApiTags('Client invites')
@Controller('client-invites')
@UseGuards(AcceptVersionGuard)
@UseFilters(AgentErrorsFilter)
export class ClientInvitesController {
  constructor(@Inject(AGENT_PROGRAM) private readonly program: AgentProgram) {}

  @Post('otp/request')
  @HttpCode(200)
  @ApiOperation({ summary: "Send a one-time code to a client's phone" })
  request(@Body() body: OtpRequestDto): Promise<ClientCodeSent> {
    this.requireSetUp();
    return this.program.clientInvites.requestCode(body.phone);
  }

  @Post('otp/verify')
  @HttpCode(200)
  @ApiOperation({ summary: 'Verify the code and get a client token' })
  verify(@Body() body: ClientOtpVerifyDto): Promise<ClientSession> {
    this.requireSetUp();
    return this.program.clientInvites.verifyCode(body.phone, body.code);
  }

  @Get()
  @UseGuards(ClientInviteGuard)
  @ApiOperation({ summary: 'The invitations waiting for the verified phone' })
  list(
    @ClientClaims() claims: AgentAccessClaims,
  ): Promise<{ items: ClientInviteView[] }> {
    this.requireSetUp();
    return this.program.clientInvites.listInvites(claims);
  }

  @Post(':id/accept')
  @HttpCode(200)
  @UseGuards(ClientInviteGuard)
  @ApiOperation({
    summary: 'Accept an invitation (creates her member account)',
  })
  accept(
    @ClientClaims() claims: AgentAccessClaims,
    @Param('id', inviteId) id: string,
  ): Promise<ClientAcceptResult> {
    this.requireSetUp();
    return this.program.clientInvites.accept(claims, id);
  }

  @Post(':id/reject')
  @HttpCode(204)
  @UseGuards(ClientInviteGuard)
  @ApiOperation({ summary: 'Reject an invitation' })
  async reject(
    @ClientClaims() claims: AgentAccessClaims,
    @Param('id', inviteId) id: string,
  ): Promise<void> {
    this.requireSetUp();
    await this.program.clientInvites.reject(claims, id);
  }

  private requireSetUp(): void {
    if (this.program.clientTokens === null || !this.program.piiSealing) {
      throw agentProgramUnavailable();
    }
  }
}
