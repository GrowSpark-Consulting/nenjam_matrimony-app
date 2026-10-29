/**
 * Whether an agent's PAN counts as verified, for `decidePayoutEligibility`'s
 * `panVerified` input. The only source is `panVerifiedAt`, which staff set with
 * `POST /admin/agents/{id}/pan/verify`; it is cleared when the PAN is replaced.
 */
import type { AgentRecord } from '../ports/agent-data-ports';

export function isPanVerified(
  agent: Pick<AgentRecord, 'panVerifiedAt'>,
): boolean {
  return agent.panVerifiedAt !== null;
}
