/**
 * `AgentCommissionPolicyPort` over the commission policy table
 * (`commission_policy_versions`): the hold days of the version in effect now,
 * the same version a new commission is created with (`findActive`).
 */
import type { CommissionPolicyRepository } from '../ports/agent-commission-ports';
import type { AgentCommissionPolicyPort } from '../ports/agent-commission-policy.port';
import type { AgentClock } from '../ports/agent-infra-ports';

export class ActivePolicyHoldDays implements AgentCommissionPolicyPort {
  constructor(
    private readonly policy: Pick<CommissionPolicyRepository, 'findActive'>,
    private readonly clock: AgentClock,
  ) {}

  async getActiveHoldDays(): Promise<number | null> {
    const active = await this.policy.findActive(this.clock.now());
    return active === null ? null : active.holdDays;
  }
}
