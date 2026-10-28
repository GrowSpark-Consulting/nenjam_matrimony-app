/**
 * Port for the active commission policy.
 *
 * Added for GET /agent/config: the hold period belongs to the commission
 * policy version (see `validateCommissionPolicyVersion`), not to the
 * agent-program settings, and the policy tables do not exist yet.
 */
export interface AgentCommissionPolicyPort {
  /** Hold days of the active policy, or null when none is active. */
  getActiveHoldDays(): Promise<number | null>;
}
