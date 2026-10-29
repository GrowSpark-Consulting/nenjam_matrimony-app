/**
 * Agent account status: which moves are allowed, and what each status may do.
 *
 * The capability table follows docs/agent-program/agent-api.openapi.yaml (the
 * "Agent account states" table and each endpoint's rules). Change the two
 * together.
 */

export type AgentStatus =
  'PENDING_APPROVAL' | 'ACTIVE' | 'REJECTED' | 'SUSPENDED' | 'TERMINATED';

// ---------------------------------------------------------------------------
// DECIDED (Raja, 28 Oct): a REJECTED agent MAY re-apply; the resubmission goes
// back to PENDING_APPROVAL for admin review (REJECTED -> PENDING_APPROVAL).
// This is the ONLY place that rule lives; it drives both the transition table
// and the `apply` capability below. Set it to false to make REJECTED final.
// ---------------------------------------------------------------------------
export const REJECTED_MAY_REAPPLY = true;

const ALLOWED_TRANSITIONS: Readonly<
  Record<AgentStatus, readonly AgentStatus[]>
> = {
  PENDING_APPROVAL: ['ACTIVE', 'REJECTED'],
  ACTIVE: ['SUSPENDED', 'TERMINATED'],
  SUSPENDED: ['ACTIVE', 'TERMINATED'],
  REJECTED: REJECTED_MAY_REAPPLY ? ['PENDING_APPROVAL'] : [],
  TERMINATED: [], // final
};

export interface AgentTransitionDecision {
  allowed: boolean;
  reason?:
    | 'UNKNOWN_STATUS'
    | 'SAME_STATUS'
    | 'TERMINATED_IS_FINAL'
    | 'TRANSITION_NOT_ALLOWED';
}

const AGENT_STATUSES: readonly string[] = Object.keys(ALLOWED_TRANSITIONS);

const isAgentStatus = (value: string): value is AgentStatus =>
  AGENT_STATUSES.includes(value);

export function canTransitionAgentStatus(
  from: string,
  to: string,
): AgentTransitionDecision {
  if (!isAgentStatus(from) || !isAgentStatus(to)) {
    return { allowed: false, reason: 'UNKNOWN_STATUS' };
  }
  if (from === to) return { allowed: false, reason: 'SAME_STATUS' };
  if (from === 'TERMINATED') {
    return { allowed: false, reason: 'TERMINATED_IS_FINAL' };
  }
  return ALLOWED_TRANSITIONS[from].includes(to)
    ? { allowed: true }
    : { allowed: false, reason: 'TRANSITION_NOT_ALLOWED' };
}

export interface AgentCapabilities {
  /** GET /agent/me */
  viewStatus: boolean;
  /** GET /agent/config */
  viewConfig: boolean;
  /** POST /agent/auth/refresh */
  refreshSession: boolean;
  /** POST /agent/auth/logout */
  logout: boolean;
  /** POST /agent/devices */
  registerDevice: boolean;
  /** POST /agent/application (applicants and, if allowed, rejected agents) */
  apply: boolean;
  /** GET /agent/referrals */
  viewReferrals: boolean;
  /** GET /agent/referral-links */
  viewReferralLinks: boolean;
  /** Links come back shareable: true. */
  shareReferralLinks: boolean;
  /** GET /agent/commissions */
  viewCommissions: boolean;
  /** GET /agent/balance */
  viewBalance: boolean;
  /** GET /agent/payouts */
  viewPayouts: boolean;
  /** PATCH /agent/me/payout-details */
  editPayoutDetails: boolean;
  /** New referrals are credited to this agent. */
  earnNewCredit: boolean;
  /** Agent-added clients (a later feature; ACTIVE only). */
  addMembers: boolean;
}

const NONE: AgentCapabilities = {
  viewStatus: false,
  viewConfig: false,
  refreshSession: false,
  logout: false,
  registerDevice: false,
  apply: false,
  viewReferrals: false,
  viewReferralLinks: false,
  shareReferralLinks: false,
  viewCommissions: false,
  viewBalance: false,
  viewPayouts: false,
  editPayoutDetails: false,
  earnNewCredit: false,
  addMembers: false,
};

const SESSION_ONLY: AgentCapabilities = {
  ...NONE,
  viewStatus: true,
  viewConfig: true,
  refreshSession: true,
  logout: true,
  registerDevice: true,
};

const CAPABILITIES: Readonly<Record<AgentStatus, AgentCapabilities>> = {
  // Status and config only (plus the session and push endpoints).
  PENDING_APPROVAL: SESSION_ONLY,
  REJECTED: { ...SESSION_ONLY, apply: REJECTED_MAY_REAPPLY },
  ACTIVE: {
    ...SESSION_ONLY,
    viewReferrals: true,
    viewReferralLinks: true,
    shareReferralLinks: true,
    viewCommissions: true,
    viewBalance: true,
    viewPayouts: true,
    editPayoutDetails: true,
    earnNewCredit: true,
    addMembers: true,
  },
  // Reads everything, but cannot share links, edit payout details or earn.
  SUSPENDED: {
    ...SESSION_ONLY,
    viewReferrals: true,
    viewReferralLinks: true,
    viewCommissions: true,
    viewBalance: true,
    viewPayouts: true,
  },
  // Read-only: status, config, commissions, balance, payouts, refresh, logout.
  TERMINATED: {
    ...NONE,
    viewStatus: true,
    viewConfig: true,
    refreshSession: true,
    logout: true,
    viewCommissions: true,
    viewBalance: true,
    viewPayouts: true,
  },
};

/** What a status may do. An unknown status may do nothing. */
export function agentCapabilitiesFor(status: string): AgentCapabilities {
  return isAgentStatus(status) ? { ...CAPABILITIES[status] } : { ...NONE };
}
