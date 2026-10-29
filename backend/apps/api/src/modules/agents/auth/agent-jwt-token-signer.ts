/**
 * The real `AgentTokenSigner`: agent access tokens as HS256 JWTs.
 *
 * - HS256 only. Tokens are signed with HS256 and verified with
 *   `algorithms: ['HS256']`, so `none`, HS384, HS512 and every asymmetric
 *   algorithm are refused.
 * - The secret, issuer and audience are constructor parameters. This file
 *   reads no environment variable and does not touch any existing JwtModule or
 *   `JWT_SECRET`: it owns a separate `JwtService` instance configured only
 *   for agents.
 * - After the signature is checked, the claims go through
 *   `validateAgentAccessClaims` (issuer, audience, scope, expiry, not-before),
 *   so `verify` returns claims only for a token that is genuine AND currently
 *   valid. Every failure is just `null`: a caller learns nothing about why.
 * - It never logs, and no error message contains a token or the secret.
 *
 * Not wired into any module. The secret is supplied by whoever builds it
 * (from configuration, set on Render before the agent endpoints go live).
 */
import { JwtService } from '@nestjs/jwt';
import type { AgentClock, AgentTokenSigner } from '../ports/agent-infra-ports';
import {
  AgentAccessClaims,
  validateAgentAccessClaims,
} from './agent-access-claims';

/** Shorter secrets are refused: HS256 needs at least 256 bits of key. */
export const MIN_AGENT_JWT_SECRET_LENGTH = 32;

export interface AgentJwtTokenSignerOptions {
  secret: string;
  issuer: string;
  audience: string;
}

export class AgentJwtTokenSigner implements AgentTokenSigner {
  private readonly jwt: JwtService;
  private readonly issuer: string;
  private readonly audience: string;

  constructor(
    options: AgentJwtTokenSignerOptions,
    private readonly clock: AgentClock,
  ) {
    if (
      typeof options.secret !== 'string' ||
      options.secret.length < MIN_AGENT_JWT_SECRET_LENGTH
    ) {
      // The length is not a secret; the value is never in the message.
      throw new RangeError(
        `The agent token secret must be at least ${MIN_AGENT_JWT_SECRET_LENGTH} characters.`,
      );
    }
    for (const key of ['issuer', 'audience'] as const) {
      if (typeof options[key] !== 'string' || options[key].length === 0) {
        throw new RangeError(`${key} must be a non-empty string.`);
      }
    }
    this.issuer = options.issuer;
    this.audience = options.audience;
    // A private instance with only the agent secret: nothing shared.
    this.jwt = new JwtService({ secret: options.secret });
  }

  async sign(claims: AgentAccessClaims): Promise<string> {
    // Signing for another issuer or audience is a programming error.
    if (claims.iss !== this.issuer || claims.aud !== this.audience) {
      throw new RangeError(
        'The claims do not match the configured issuer and audience.',
      );
    }
    return this.jwt.signAsync({ ...claims }, { algorithm: 'HS256' });
  }

  async verify(token: string): Promise<AgentAccessClaims | null> {
    const checked = await this.check(token);
    return checked.ok ? checked.claims : null;
  }

  /**
   * Like `verify`, but says whether a GENUINE token has merely expired (so a
   * client knows to refresh). The reason is only ever EXPIRED after the
   * signature has been checked: a forged or altered token is always INVALID.
   */
  async check(token: string): Promise<AgentTokenCheck> {
    if (typeof token !== 'string' || token.length === 0) {
      return { ok: false, reason: 'INVALID' };
    }

    let payload: unknown;
    try {
      payload = await this.jwt.verifyAsync<Record<string, unknown>>(token, {
        algorithms: ['HS256'],
        // Time is judged below, by the shared claims check, with our clock.
        ignoreExpiration: true,
        ignoreNotBefore: true,
      });
    } catch {
      // Bad signature, wrong algorithm, malformed: no detail is passed on.
      return { ok: false, reason: 'INVALID' };
    }

    const checked = validateAgentAccessClaims(payload, {
      issuer: this.issuer,
      audience: this.audience,
      now: this.clock.now(),
    });
    if (checked.ok) return { ok: true, claims: checked.claims };
    return {
      ok: false,
      reason: checked.reason === 'EXPIRED' ? 'EXPIRED' : 'INVALID',
    };
  }
}

/** What `AgentJwtTokenSigner.check` answers. */
export type AgentTokenCheck =
  | { ok: true; claims: AgentAccessClaims }
  | { ok: false; reason: 'INVALID' | 'EXPIRED' };

/** The part of the signer the agent guard needs. */
export interface AgentTokenChecker {
  check(token: string): Promise<AgentTokenCheck>;
}
