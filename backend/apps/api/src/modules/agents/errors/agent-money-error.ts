/**
 * The error the commission, payout and admin services throw for a refusal a
 * client can act on. Like `AgentServiceError`, it carries a `code` (spelled
 * as in `docs/agent-program/agent-admin-api.openapi.yaml`) and the extras the
 * contract lists; a later controller maps it to an HTTP status. Nothing here
 * knows about HTTP.
 */
export type AgentMoneyErrorCode =
  | 'VALIDATION_FAILED'
  | 'AGENT_NOT_FOUND'
  | 'REFERRAL_NOT_FOUND'
  | 'COMMISSION_NOT_FOUND'
  | 'PAYOUT_NOT_FOUND'
  | 'AGENT_TRANSITION_NOT_ALLOWED'
  | 'COMMISSION_STATUS_NOT_ALLOWED'
  | 'COMMISSION_IN_PAYOUT'
  | 'COMMISSION_AMOUNT_NOT_SET'
  | 'PAYOUT_NOT_ELIGIBLE'
  | 'PAYOUT_STATUS_NOT_ALLOWED'
  | 'REFERENCE_ALREADY_USED'
  | 'PAN_NOT_SET'
  | 'PAN_ALREADY_VERIFIED'
  | 'PAYOUT_DETAILS_NOT_SET'
  | 'PAYOUT_DETAILS_ALREADY_VERIFIED'
  | 'CODE_ALREADY_REPLACED'
  | 'ALREADY_ATTRIBUTED'
  | 'CONCURRENT_CHANGE';

export interface AgentMoneyErrorOptions {
  /** For PAYOUT_NOT_ELIGIBLE: every reason, in a fixed order. */
  reasons?: string[];
  /** For AGENT_TRANSITION_NOT_ALLOWED / refusals about an agent: the current status. */
  agentStatus?: string;
  /** For AGENT_TRANSITION_NOT_ALLOWED: SAME_STATUS, TERMINATED_IS_FINAL, TRANSITION_NOT_ALLOWED. */
  refusal?: string;
  /** For VALIDATION_FAILED: which fields, never their values. */
  fields?: string[];
}

export class AgentMoneyError extends Error {
  readonly reasons?: string[];
  readonly agentStatus?: string;
  readonly refusal?: string;
  readonly fields?: string[];

  constructor(
    public readonly code: AgentMoneyErrorCode,
    options: AgentMoneyErrorOptions = {},
  ) {
    super(code);
    this.name = 'AgentMoneyError';
    this.reasons = options.reasons;
    this.agentStatus = options.agentStatus;
    this.refusal = options.refusal;
    this.fields = options.fields;
  }
}
