/**
 * Ports for infrastructure the agent program owns: the clock and the
 * access-token signer.
 */
import type { AgentAccessClaims } from '../auth/agent-access-claims';

export interface AgentClock {
  now(): Date;
}

/**
 * Signs and verifies agent access tokens.
 *
 * `verify` only answers "is this token genuine and untampered?" and returns
 * its claims, or null. Expiry, audience, issuer and scope are checked by the
 * existing `validateAgentAccessClaims`, not here.
 *
 * PENDING DECISION (Ishu): how tokens are signed (Node `crypto` HMAC, or an
 * approved JWT library). Nothing real implements this port yet.
 */
export interface AgentTokenSigner {
  sign(claims: AgentAccessClaims): Promise<string>;
  verify(token: string): Promise<AgentAccessClaims | null>;
}
