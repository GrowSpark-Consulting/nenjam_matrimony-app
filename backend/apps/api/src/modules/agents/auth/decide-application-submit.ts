/**
 * The rule for POST /agent/application: may this caller submit an application,
 * and does it create a new agent or resubmit a rejected one?
 *
 * Pure, plain string inputs. Whether a rejected agent may re-apply is passed in
 * (`rejectedMayReapply`) rather than decided here.
 */

export interface ApplicationSubmitInput {
  /** Scope of the caller's agent access token: 'AGENT' or 'APPLICANT'. */
  tokenScope: string;
  /** Status of the caller's agent record, or null when there is none. */
  existingAgentStatus: string | null;
  rejectedMayReapply: boolean;
  /** Another agent record already exists for this phone. */
  phoneAlreadyHasAgent: boolean;
}

export type ApplicationSubmitRejectReason =
  | 'BAD_SCOPE'
  | 'SCOPE_MISMATCH'
  | 'PHONE_ALREADY_REGISTERED'
  | 'REAPPLY_NOT_ALLOWED'
  | 'ALREADY_PENDING'
  | 'ALREADY_AN_AGENT'
  | 'UNKNOWN_STATUS';

export type ApplicationSubmitDecision =
  | { allowed: true; action: 'CREATE_PENDING' | 'RESUBMIT_PENDING' }
  | { allowed: false; reason: ApplicationSubmitRejectReason };

export function decideApplicationSubmit(
  input: ApplicationSubmitInput,
): ApplicationSubmitDecision {
  if (input.tokenScope !== 'APPLICANT' && input.tokenScope !== 'AGENT') {
    return { allowed: false, reason: 'BAD_SCOPE' };
  }

  // No agent record for this caller.
  if (input.existingAgentStatus === null) {
    if (input.phoneAlreadyHasAgent) {
      return { allowed: false, reason: 'PHONE_ALREADY_REGISTERED' };
    }
    // An AGENT token always belongs to an agent record; without one the token
    // and the data disagree, so refuse rather than create a second agent.
    if (input.tokenScope !== 'APPLICANT') {
      return { allowed: false, reason: 'SCOPE_MISMATCH' };
    }
    return { allowed: true, action: 'CREATE_PENDING' };
  }

  switch (input.existingAgentStatus) {
    case 'REJECTED':
      // PENDING DECISION (Raja): may a rejected agent re-apply? The answer is
      // the `rejectedMayReapply` input (REJECTED_MAY_REAPPLY in
      // agent/agent-status.ts); this function does not decide it.
      return input.rejectedMayReapply
        ? { allowed: true, action: 'RESUBMIT_PENDING' }
        : { allowed: false, reason: 'REAPPLY_NOT_ALLOWED' };
    case 'PENDING_APPROVAL':
      return { allowed: false, reason: 'ALREADY_PENDING' };
    case 'ACTIVE':
    case 'SUSPENDED':
    case 'TERMINATED':
      return { allowed: false, reason: 'ALREADY_AN_AGENT' };
    default:
      return { allowed: false, reason: 'UNKNOWN_STATUS' };
  }
}
