/**
 * Turns the agent services' refusals into the contract's error bodies
 * (`{ statusCode, error, code, message, ...extras }`, docs/agent-program/
 * agent-api.openapi.yaml). Bound to the agent-facing and member referral
 * controllers only; any other error (Nest's HttpExceptions, Shaaz's 503s)
 * is left to Nest.
 *
 * The status of each code is the table in the service that throws it
 * (agent-application.service.ts, agent-referral-code.service.ts, and the
 * sign-in service's OTP and refresh refusals). Two cases have no table:
 * an `AgentConflictError` that no service caught (a race between two
 * requests) is 409 CONCURRENT_CHANGE, and `AgentConfigError` (a setting or
 * the commission policy is not set) is 503 AGENT_PROGRAM_UNAVAILABLE.
 */
import { ArgumentsHost, Catch, ExceptionFilter, Logger } from '@nestjs/common';
import type { Response } from 'express';
import { AgentConfigError } from '../config/agent-config.service';
import {
  AgentServiceError,
  type AgentServiceErrorCode,
} from '../errors/agent-service-error';
import { AgentConflictError } from '../ports/agent-data-ports';

interface Mapping {
  status: number;
  /** The contract's `code`; the service's own code when absent. */
  code?: string;
  message: string;
}

export const AGENT_ERROR_HTTP: Record<AgentServiceErrorCode, Mapping> = {
  VALIDATION_FAILED: { status: 400, message: 'The request is not valid.' },
  UNAUTHORIZED: {
    status: 401,
    message: 'A valid agent access token is required.',
  },
  RATE_LIMITED: { status: 429, message: 'Too many attempts. Try again later.' },
  OTP_INVALID: { status: 401, message: 'The code is not right.' },
  OTP_EXPIRED: { status: 401, message: 'The code has expired.' },
  REFRESH_TOKEN_INVALID: { status: 401, message: 'Sign in again.' },
  REFRESH_TOKEN_EXPIRED: { status: 401, message: 'Sign in again.' },
  REFRESH_TOKEN_REUSED: {
    status: 401,
    message: 'This session was ended everywhere. Sign in again.',
  },
  AGENT_NOT_ACTIVE: {
    status: 403,
    message: 'Not available in this account status.',
  },
  AGENT_NOT_FOUND: { status: 404, message: 'No application yet.' },
  REFERRAL_NOT_FOUND: { status: 404, message: 'No such referral.' },
  CODE_NOT_FOUND: { status: 404, message: 'This code cannot be used.' },
  ALREADY_ATTRIBUTED: {
    status: 409,
    message: 'Already credited to an agent.',
  },
  SELF_REFERRAL: { status: 422, message: 'You cannot use your own code.' },
  ALREADY_PAID: {
    status: 422,
    message: 'A code can no longer be added after a plan was bought.',
  },
  PHONE_NOT_VERIFIED: {
    status: 422,
    message: 'A verified phone number is needed to use a code.',
  },
  // The application refusals (decideApplicationSubmit), per the table in
  // agent-application.service.ts.
  BAD_SCOPE: {
    status: 401,
    code: 'UNAUTHORIZED',
    message: 'A valid agent access token is required.',
  },
  SCOPE_MISMATCH: {
    status: 401,
    code: 'UNAUTHORIZED',
    message: 'A valid agent access token is required.',
  },
  PHONE_ALREADY_REGISTERED: {
    status: 409,
    code: 'APPLICATION_EXISTS',
    message: 'This phone already has an agent account. Sign in again.',
  },
  ALREADY_PENDING: {
    status: 409,
    code: 'APPLICATION_EXISTS',
    message: 'Your application is already under review.',
  },
  ALREADY_AN_AGENT: {
    status: 409,
    code: 'APPLICATION_EXISTS',
    message: 'You are already an agent.',
  },
  REAPPLY_NOT_ALLOWED: {
    status: 403,
    code: 'AGENT_NOT_ACTIVE',
    message: 'Applying again is not possible.',
  },
  UNKNOWN_STATUS: {
    status: 500,
    code: 'INTERNAL_ERROR',
    message: 'Something went wrong.',
  },
};

const ERROR_NAME: Record<number, string> = {
  400: 'Bad Request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not Found',
  409: 'Conflict',
  422: 'Unprocessable Entity',
  429: 'Too Many Requests',
  500: 'Internal Server Error',
  503: 'Service Unavailable',
};

@Catch(AgentServiceError, AgentConflictError, AgentConfigError)
export class AgentErrorsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AgentErrorsFilter.name);

  catch(
    exception: AgentServiceError | AgentConflictError | AgentConfigError,
    host: ArgumentsHost,
  ): void {
    const response = host.switchToHttp().getResponse<Response>();
    if (exception instanceof AgentConflictError) {
      send(response, 409, {
        code: 'CONCURRENT_CHANGE',
        message: 'Something changed at the same time. Try again.',
      });
      return;
    }
    if (exception instanceof AgentConfigError) {
      // Names setting keys only, never values.
      this.logger.warn(exception.message);
      send(response, 503, {
        code: 'AGENT_PROGRAM_UNAVAILABLE',
        message: 'The agent program is not available yet.',
      });
      return;
    }
    const mapping = AGENT_ERROR_HTTP[exception.code];
    if (exception.retryAfterSeconds !== undefined) {
      response.setHeader('Retry-After', String(exception.retryAfterSeconds));
    }
    send(response, mapping.status, {
      code: mapping.code ?? exception.code,
      message:
        exception.code === 'VALIDATION_FAILED' && exception.fields?.length
          ? exception.fields.map((field) => `${field} is not valid`)
          : mapping.message,
      ...(exception.agentStatus !== undefined && {
        agentStatus: exception.agentStatus,
      }),
    });
  }
}

function send(
  response: Response,
  status: number,
  body: { code: string; message: string | string[]; agentStatus?: string },
): void {
  response.status(status).json({
    statusCode: status,
    error: ERROR_NAME[status] ?? 'Error',
    ...body,
  });
}
