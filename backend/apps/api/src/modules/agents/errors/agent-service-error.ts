/**
 * The one error the agent services throw for a refusal that a client can act
 * on. A later controller or exception filter maps `code` to an HTTP status;
 * the services know nothing about HTTP.
 *
 * Codes that appear in the API contract (`Error.code`) keep that spelling.
 * The application refusals are the reasons from `decideApplicationSubmit`,
 * kept as they are so the mapping table in the application service is the
 * only place they are translated.
 */
import type { ApplicationSubmitRejectReason } from '../auth/decide-application-submit';

export type AgentServiceErrorCode =
  | 'VALIDATION_FAILED'
  | 'UNAUTHORIZED'
  | 'RATE_LIMITED'
  | 'OTP_INVALID'
  | 'OTP_EXPIRED'
  | 'REFRESH_TOKEN_INVALID'
  | 'REFRESH_TOKEN_EXPIRED'
  | 'REFRESH_TOKEN_REUSED'
  | 'AGENT_NOT_ACTIVE'
  | 'AGENT_NOT_FOUND'
  | ApplicationSubmitRejectReason;

export interface AgentServiceErrorOptions {
  /** For RATE_LIMITED from a send: seconds until it may be tried again. */
  retryAfterSeconds?: number;
  /** For AGENT_NOT_ACTIVE: the status that was refused. */
  agentStatus?: string;
  /** For VALIDATION_FAILED: which fields, never their values. */
  fields?: string[];
}

export class AgentServiceError extends Error {
  readonly retryAfterSeconds?: number;
  readonly agentStatus?: string;
  readonly fields?: string[];

  constructor(
    public readonly code: AgentServiceErrorCode,
    options: AgentServiceErrorOptions = {},
  ) {
    super(code);
    this.name = 'AgentServiceError';
    this.retryAfterSeconds = options.retryAfterSeconds;
    this.agentStatus = options.agentStatus;
    this.fields = options.fields;
  }
}
