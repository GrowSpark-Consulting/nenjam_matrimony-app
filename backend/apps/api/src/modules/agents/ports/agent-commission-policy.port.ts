/**
 * Port for the active commission policy.
 *
 * Used by GET /agent/config: the hold period belongs to the commission
 * policy version (see `validateCommissionPolicyVersion`), not to the
 * agent-program settings. Backed by `ActivePolicyHoldDays` over the
 * `commission_policy_versions` table.
 */
export interface AgentCommissionPolicyPort {
  /** Hold days of the active policy, or null when none is active. */
  getActiveHoldDays(): Promise<number | null>;
}
