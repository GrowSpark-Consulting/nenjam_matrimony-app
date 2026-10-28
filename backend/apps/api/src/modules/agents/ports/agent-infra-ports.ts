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
 * `verify` returns the claims only for a token that is genuine AND currently
 * valid for this deployment (signature, issuer, audience, scope, expiry), and
 * `null` for anything else, without saying why. The real implementation is
 * `AgentJwtTokenSigner` (HS256 through @nestjs/jwt); tests use a fake.
 */
export interface AgentTokenSigner {
  sign(claims: AgentAccessClaims): Promise<string>;
  verify(token: string): Promise<AgentAccessClaims | null>;
}
