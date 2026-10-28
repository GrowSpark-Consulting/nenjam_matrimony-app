/** In-memory commission policy port. Tests only. */
import type { AgentCommissionPolicyPort } from '../ports/agent-commission-policy.port';

export class FakeAgentCommissionPolicy implements AgentCommissionPolicyPort {
  constructor(private holdDays: number | null) {}

  set(holdDays: number | null): void {
    this.holdDays = holdDays;
  }

  getActiveHoldDays(): Promise<number | null> {
    return Promise.resolve(this.holdDays);
  }
}
