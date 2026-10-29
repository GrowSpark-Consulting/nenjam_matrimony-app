/**
 * The rule for the daily commission approval job: given one commission and
 * the facts about it, what status does it move to?
 *
 * Pure: the caller loads the commission and its agent, precomputes
 * `profileEligible`, and passes `now`. The settings (auto-approve, whether a
 * commission base is configured) arrive as parameters; the hold length is
 * already baked into `holdUntil`.
 */

export type OpenCommissionStatus =
  'ON_HOLD' | 'AWAITING_VERIFICATION' | 'IN_REVIEW' | 'FROZEN' | 'READY';

export type CommissionTransitionTarget = OpenCommissionStatus | 'APPROVED';

export type CommissionTransitionReason =
  | 'ADMIN_REVIEW'
  | 'AGENT_SUSPENDED'
  | 'AGENT_TERMINATED'
  | 'AWAITING_ADMIN'
  | 'BASE_NOT_SET'
  | 'HOLD_RUNNING'
  | 'PROFILE_NOT_VERIFIED'
  | 'AUTO_APPROVED'
  | 'READY_FOR_ADMIN';

export interface CommissionTransitionInput {
  status: OpenCommissionStatus;
  now: Date;
  /** The hold is over when now >= holdUntil. */
  holdUntil: Date;
  /** AgentStatus of the earning agent; anything other than the two below is not blocking. */
  agentStatus: string;
  autoApprove: boolean;
  /** Precomputed by the caller (see isProfileEligibleForCommission). */
  profileEligible: boolean;
  commissionBaseConfigured: boolean;
}

export interface CommissionTransition {
  next: CommissionTransitionTarget;
  reason: CommissionTransitionReason;
}

// ---------------------------------------------------------------------------
// DECIDED (Raja, 28 Oct): a TERMINATED agent's waiting commissions stay FROZEN,
// the same as a suspended agent's, until Raja decides otherwise; commission
// already APPROVED is still paid (payout eligibility treats TERMINATED as
// payable). This is the ONLY place that rule lives; change it here.
// ---------------------------------------------------------------------------
function frozenForAgent(
  agentStatus: string,
): CommissionTransitionReason | null {
  if (agentStatus === 'SUSPENDED') return 'AGENT_SUSPENDED';
  if (agentStatus === 'TERMINATED') return 'AGENT_TERMINATED';
  return null;
}

export function decideCommissionTransition(
  input: CommissionTransitionInput,
): CommissionTransition {
  if (
    Number.isNaN(input.now.getTime()) ||
    Number.isNaN(input.holdUntil.getTime())
  ) {
    // An invalid date compares false both ways and would fall through to
    // APPROVED, so refuse it.
    throw new RangeError('now and holdUntil must be valid dates.');
  }

  // 1. An admin is deciding this one.
  if (input.status === 'IN_REVIEW') {
    return { next: 'IN_REVIEW', reason: 'ADMIN_REVIEW' };
  }

  // 2. Nothing moves forward for a suspended or terminated agent.
  const frozenReason = frozenForAgent(input.agentStatus);
  if (frozenReason) return { next: 'FROZEN', reason: frozenReason };

  // 3. Only an admin moves READY to APPROVED.
  if (input.status === 'READY') {
    return { next: 'READY', reason: 'AWAITING_ADMIN' };
  }

  // A FROZEN commission whose agent is ACTIVE again is evaluated from here on,
  // like the others.

  // 4. No commission base configured: leave it as it is.
  if (!input.commissionBaseConfigured) {
    return { next: input.status, reason: 'BASE_NOT_SET' };
  }

  // 5. Still inside the hold period.
  if (input.now.getTime() < input.holdUntil.getTime()) {
    return { next: 'ON_HOLD', reason: 'HOLD_RUNNING' };
  }

  // 6. Hold is over but the profile does not qualify (yet).
  if (!input.profileEligible) {
    return { next: 'AWAITING_VERIFICATION', reason: 'PROFILE_NOT_VERIFIED' };
  }

  // 7. Ready to pay: straight to APPROVED, or wait for an admin.
  return input.autoApprove
    ? { next: 'APPROVED', reason: 'AUTO_APPROVED' }
    : { next: 'READY', reason: 'READY_FOR_ADMIN' };
}
