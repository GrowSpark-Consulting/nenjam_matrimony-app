/**
 * Turns the agent services' refusals into the admin contract's error bodies
 * (`{ statusCode, error, code, message, ...extras }`). Anything else is left
 * to Nest. Bound to the agent admin controllers only.
 */
import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpStatus,
} from '@nestjs/common';
import type { Response } from 'express';
import { AgentConfigError } from '../config/agent-config.service';
import {
  AgentMoneyError,
  type AgentMoneyErrorCode,
} from '../errors/agent-money-error';
import { AgentPermissionDeniedError } from '../ports/agent-platform-ports';

const STATUS: Partial<Record<AgentMoneyErrorCode, number>> = {
  VALIDATION_FAILED: HttpStatus.BAD_REQUEST,
  AGENT_NOT_FOUND: HttpStatus.NOT_FOUND,
  REFERRAL_NOT_FOUND: HttpStatus.NOT_FOUND,
  COMMISSION_NOT_FOUND: HttpStatus.NOT_FOUND,
  PAYOUT_NOT_FOUND: HttpStatus.NOT_FOUND,
  AGENT_TRANSITION_NOT_ALLOWED: HttpStatus.CONFLICT,
  AGENT_STATUS_NOT_ALLOWED: HttpStatus.CONFLICT,
  CONCURRENT_CHANGE: HttpStatus.CONFLICT,
  ADMIN_STEP_UP_REQUIRED: HttpStatus.UNAUTHORIZED,
};

const ERROR_NAME: Record<number, string> = {
  400: 'Bad Request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not Found',
  409: 'Conflict',
  500: 'Internal Server Error',
};

const MESSAGE: Partial<Record<AgentMoneyErrorCode, string>> = {
  VALIDATION_FAILED: 'The request is not valid.',
  AGENT_NOT_FOUND: 'No agent with this id.',
  AGENT_TRANSITION_NOT_ALLOWED:
    'An agent in this status cannot be moved to the one asked for.',
  CONCURRENT_CHANGE: 'The agent changed meanwhile; reload and try again.',
};

@Catch(AgentMoneyError, AgentPermissionDeniedError, AgentConfigError)
export class AgentAdminErrorsFilter implements ExceptionFilter {
  catch(
    exception: AgentMoneyError | AgentPermissionDeniedError | AgentConfigError,
    host: ArgumentsHost,
  ): void {
    const response = host.switchToHttp().getResponse<Response>();
    if (exception instanceof AgentConfigError) {
      // A required setting is not seeded: the contract's SettingsNotConfigured.
      response.status(HttpStatus.SERVICE_UNAVAILABLE).json({
        statusCode: 503,
        error: 'Service Unavailable',
        code: 'SETTINGS_NOT_CONFIGURED',
        message: 'A required setting is not configured.',
        missing: exception.missing,
      });
      return;
    }
    if (exception instanceof AgentPermissionDeniedError) {
      // The same body as the admin guard's refusal.
      const missing = /requires ([\w.]+)\./.exec(exception.message)?.[1];
      response.status(HttpStatus.FORBIDDEN).json({
        statusCode: 403,
        error: 'Forbidden',
        code: 'ADMIN_PERMISSION_DENIED',
        message: exception.message,
        ...(missing !== undefined && { missing: [missing] }),
      });
      return;
    }
    const status = STATUS[exception.code] ?? HttpStatus.CONFLICT;
    response.status(status).json({
      statusCode: status,
      error: ERROR_NAME[status] ?? 'Error',
      code: exception.code,
      message: MESSAGE[exception.code] ?? exception.code,
      ...(exception.fields !== undefined && { fields: exception.fields }),
      ...(exception.agentStatus !== undefined && {
        agentStatus: exception.agentStatus,
      }),
      ...(exception.refusal !== undefined && { refusal: exception.refusal }),
      ...(exception.reasons !== undefined && { reasons: exception.reasons }),
    });
  }
}
