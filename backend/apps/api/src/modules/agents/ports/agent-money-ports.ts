/**
 * Read-only ports the commission handlers need from other parts of the
 * platform. The real adapters wait for Shaaz's Payments PR (payment source
 * hash on the payment) and for a decision on member profile verification;
 * until then the services run against fakes.
 */

/** Abuse check: has this payment source (card, UPI id) paid for another member? */
export interface AgentPaymentSourcePort {
  /**
   * True when `paymentSourceHash` was already used by a payment for a member
   * other than `memberId`, ignoring the payment `excludePaymentId` itself.
   * The hash is opaque; it is never logged.
   */
  wasUsedByAnotherMember(input: {
    paymentSourceHash: string;
    memberId: string;
    excludePaymentId: string;
  }): Promise<boolean>;
}

/**
 * Whether a member's profile counts as verified, for the
 * `commission.require_verified_profile` setting. Only consulted when that
 * setting is on (today it is off: there is no KYC).
 */
export interface AgentMemberProfilePort {
  isProfileVerified(memberId: string): Promise<boolean>;
}

/**
 * The status-change entries of one agent (`agent.approve`, `agent.reject`,
 * `agent.pause`, `agent.resume`, `agent.terminate`) read from the audit log,
 * and ONLY those: `agent.view` does not grant `audit.view`. The real adapter
 * reads `audit_logs` (Shaaz's audit service); until then a fake.
 */
export interface AgentStatusHistoryPort {
  listForAgent(
    agentId: string,
    tx?: import('./agent-unit-of-work.port').AgentTx,
  ): Promise<
    Array<{ action: string; at: Date; actorId: string | null; reason: string | null }>
  >;
}
