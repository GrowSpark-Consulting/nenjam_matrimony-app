/**
 * HTTP pieces shared by the agent-facing and member referral routes:
 *
 * - `AcceptVersionGuard`: `Accept-Version` missing = 1; anything but 1 is
 *   406 UNSUPPORTED_VERSION. Every answer (errors included) carries
 *   `Content-Version: 1`.
 * - `AgentAccessGuard` + `@AgentScopes(...)`: a Bearer agent access token,
 *   verified by our HS256 signer (secret AGENT_JWT_SECRET). Missing, bad or
 *   wrong-scope token: 401 UNAUTHORIZED; expired: 401 TOKEN_EXPIRED; no
 *   secret configured: 503 AGENT_PROGRAM_UNAVAILABLE. A route accepts only
 *   the scopes it names (default AGENT only), so an applicant token can call
 *   nothing but what explicitly allows APPLICANT.
 * - `@AgentClaims()`: the verified claims the guard attached.
 * - `ClientInviteGuard` + `@ClientClaims()`: the same for the client token
 *   of agent-added clients (Way 2): its own signer and audience, CLIENT
 *   scope only, so an agent token fails here and a client token fails on
 *   every route behind `AgentAccessGuard`.
 */
import {
  CanActivate,
  createParamDecorator,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  SetMetadata,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request, Response } from 'express';
import type {
  AgentAccessClaims,
  AgentTokenScope,
} from '../auth/agent-access-claims';
import {
  AGENT_PROGRAM,
  agentProgramUnavailable,
  type AgentProgram,
} from './agent-program';

export const API_VERSION = '1';

@Injectable()
export class AcceptVersionGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const http = context.switchToHttp();
    http.getResponse<Response>().setHeader('Content-Version', API_VERSION);
    const raw = http.getRequest<Request>().headers['accept-version'];
    const asked = Array.isArray(raw) ? raw.join(',') : raw;
    if (asked === undefined || asked.trim() === API_VERSION) return true;
    throw new HttpException(
      {
        statusCode: HttpStatus.NOT_ACCEPTABLE,
        error: 'Not Acceptable',
        code: 'UNSUPPORTED_VERSION',
        message: `Only Accept-Version ${API_VERSION} is supported.`,
      },
      HttpStatus.NOT_ACCEPTABLE,
    );
  }
}

const SCOPES = 'agent:scopes';

/** Which token scopes may call the route. Default (no decorator): AGENT. */
export const AgentScopes = (...scopes: AgentTokenScope[]) =>
  SetMetadata(SCOPES, scopes);

interface RequestWithAgent extends Request {
  agentClaims?: AgentAccessClaims;
  clientClaims?: AgentAccessClaims;
}

export function unauthorized(code: 'UNAUTHORIZED' | 'TOKEN_EXPIRED') {
  return new UnauthorizedException({
    statusCode: 401,
    error: 'Unauthorized',
    code,
    message:
      code === 'TOKEN_EXPIRED'
        ? 'The access token has expired. Refresh it and retry.'
        : 'A valid agent access token is required.',
  });
}

function clientUnauthorized(code: 'UNAUTHORIZED' | 'TOKEN_EXPIRED') {
  return new UnauthorizedException({
    statusCode: 401,
    error: 'Unauthorized',
    code,
    message:
      code === 'TOKEN_EXPIRED'
        ? 'The client token has expired. Verify your phone again.'
        : 'A valid client token is required.',
  });
}

const bearerOf = (request: Request): string | null => {
  const header = request.headers.authorization;
  const match =
    typeof header === 'string' ? /^Bearer ([^\s]+)$/.exec(header) : null;
  return match ? match[1] : null;
};

@Injectable()
export class AgentAccessGuard implements CanActivate {
  constructor(
    @Inject(AGENT_PROGRAM) private readonly program: AgentProgram,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const tokens = this.program.tokens;
    if (tokens === null) throw agentProgramUnavailable();

    const request = context.switchToHttp().getRequest<RequestWithAgent>();
    const header = request.headers.authorization;
    const match =
      typeof header === 'string' ? /^Bearer ([^\s]+)$/.exec(header) : null;
    if (!match) throw unauthorized('UNAUTHORIZED');

    const checked = await tokens.check(match[1]);
    if (!checked.ok) {
      throw unauthorized(
        checked.reason === 'EXPIRED' ? 'TOKEN_EXPIRED' : 'UNAUTHORIZED',
      );
    }
    const allowed = this.reflector.getAllAndOverride<
      AgentTokenScope[] | undefined
    >(SCOPES, [context.getHandler(), context.getClass()]) ?? ['AGENT'];
    if (!allowed.includes(checked.claims.scope)) {
      throw unauthorized('UNAUTHORIZED');
    }
    request.agentClaims = checked.claims;
    return true;
  }
}

/** A Bearer client token (scope CLIENT, the client audience). */
@Injectable()
export class ClientInviteGuard implements CanActivate {
  constructor(@Inject(AGENT_PROGRAM) private readonly program: AgentProgram) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const tokens = this.program.clientTokens;
    if (tokens === null) throw agentProgramUnavailable();
    const request = context.switchToHttp().getRequest<RequestWithAgent>();
    const token = bearerOf(request);
    if (token === null) throw clientUnauthorized('UNAUTHORIZED');
    const checked = await tokens.check(token);
    if (!checked.ok) {
      throw clientUnauthorized(
        checked.reason === 'EXPIRED' ? 'TOKEN_EXPIRED' : 'UNAUTHORIZED',
      );
    }
    // The client signer only ever accepts CLIENT; checked again here.
    if (checked.claims.scope !== 'CLIENT') {
      throw clientUnauthorized('UNAUTHORIZED');
    }
    request.clientClaims = checked.claims;
    return true;
  }
}

export const ClientClaims = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AgentAccessClaims => {
    const claims = context
      .switchToHttp()
      .getRequest<RequestWithAgent>().clientClaims;
    // Only reachable on a route without ClientInviteGuard: a programming error.
    if (!claims) throw clientUnauthorized('UNAUTHORIZED');
    return claims;
  },
);

export const AgentClaims = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AgentAccessClaims => {
    const claims = context
      .switchToHttp()
      .getRequest<RequestWithAgent>().agentClaims;
    // Only reachable on a route without AgentAccessGuard: a programming error.
    if (!claims) throw unauthorized('UNAUTHORIZED');
    return claims;
  },
);
