/**
 * Claims for the agent's own access token (not Firebase).
 *
 * This only builds and checks the claim set. It does NOT sign the token or
 * verify a signature; that comes later with the token package. The lifetime,
 * issuer and audience are parameters, never constants here.
 */

/**
 * AGENT and APPLICANT: agent portal tokens. CLIENT: an agent-added client
 * who proved her phone (Way 2); signed with its own audience, so it never
 * passes for an agent token and an agent token never passes for it.
 */
export type AgentTokenScope = 'AGENT' | 'APPLICANT' | 'CLIENT';

/** The scopes an agent portal token may carry (the default of the check). */
export const AGENT_PORTAL_SCOPES: readonly AgentTokenScope[] = [
  'AGENT',
  'APPLICANT',
];

export interface AgentAccessClaims {
  /**
   * AGENT: the agent id. APPLICANT: the phone hash (no agent exists yet).
   * CLIENT: the client's phone, SEALED (`agent.client_phone`), so every
   * pepper version of its hash can be computed; never the plain phone.
   */
  sub: string;
  scope: AgentTokenScope;
  aud: string;
  iss: string;
  /** Issued at, whole seconds since the epoch. */
  iat: number;
  /** Expires at, whole seconds since the epoch. */
  exp: number;
}

export interface BuildAgentAccessClaimsInput {
  agentId: string | null;
  phoneHash: string;
  /** CLIENT only: the sealed phone (see `AgentAccessClaims.sub`). */
  clientRef?: string;
  scope: AgentTokenScope;
  now: Date;
  ttlSeconds: number;
  issuer: string;
  audience: string;
}

const isNonEmptyString = (value: unknown): value is string =>
  typeof value === 'string' && value.length > 0;

const isValidDate = (value: unknown): value is Date =>
  value instanceof Date && !Number.isNaN(value.getTime());

export function buildAgentAccessClaims(
  input: BuildAgentAccessClaimsInput,
): AgentAccessClaims {
  if (!isValidDate(input.now)) {
    throw new RangeError('now must be a valid date.');
  }
  if (!Number.isSafeInteger(input.ttlSeconds) || input.ttlSeconds <= 0) {
    throw new RangeError('ttlSeconds must be a positive integer.');
  }
  if (!isNonEmptyString(input.issuer)) {
    throw new RangeError('issuer must be a non-empty string.');
  }
  if (!isNonEmptyString(input.audience)) {
    throw new RangeError('audience must be a non-empty string.');
  }

  let sub: string;
  if (input.scope === 'AGENT') {
    if (!isNonEmptyString(input.agentId)) {
      throw new RangeError('An AGENT token needs an agentId.');
    }
    sub = input.agentId;
  } else if (input.scope === 'APPLICANT') {
    if (input.agentId !== null) {
      throw new RangeError('An APPLICANT token has no agentId.');
    }
    if (!isNonEmptyString(input.phoneHash)) {
      throw new RangeError('An APPLICANT token needs a phoneHash.');
    }
    sub = input.phoneHash;
  } else if (input.scope === 'CLIENT') {
    if (input.agentId !== null) {
      throw new RangeError('A CLIENT token has no agentId.');
    }
    if (!isNonEmptyString(input.clientRef)) {
      throw new RangeError('A CLIENT token needs a clientRef.');
    }
    sub = input.clientRef;
  } else {
    throw new RangeError("scope must be 'AGENT', 'APPLICANT' or 'CLIENT'.");
  }

  const iat = Math.floor(input.now.getTime() / 1000);
  return {
    sub,
    scope: input.scope,
    aud: input.audience,
    iss: input.issuer,
    iat,
    exp: iat + input.ttlSeconds,
  };
}

export type AgentAccessClaimsRejectReason =
  | 'MALFORMED'
  | 'WRONG_ISSUER'
  | 'WRONG_AUDIENCE'
  | 'EXPIRED'
  | 'NOT_YET_VALID'
  | 'BAD_SCOPE';

export interface ExpectedAgentAccessClaims {
  issuer: string;
  audience: string;
  now: Date;
  /** The scopes this audience accepts. Default: AGENT and APPLICANT. */
  scopes?: readonly AgentTokenScope[];
}

export type AgentAccessClaimsCheck =
  | { ok: true; claims: AgentAccessClaims }
  | { ok: false; reason: AgentAccessClaimsRejectReason };

const isEpochSeconds = (value: unknown): value is number =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;

/**
 * Checks a decoded claim set. No clock tolerance: expired exactly at `exp`,
 * not yet valid one second before `iat`. Extra claims are ignored and not
 * returned.
 */
export function validateAgentAccessClaims(
  claims: unknown,
  expected: ExpectedAgentAccessClaims,
): AgentAccessClaimsCheck {
  if (!isValidDate(expected.now)) {
    throw new RangeError('now must be a valid date.');
  }
  if (!isNonEmptyString(expected.issuer)) {
    throw new RangeError('issuer must be a non-empty string.');
  }
  if (!isNonEmptyString(expected.audience)) {
    throw new RangeError('audience must be a non-empty string.');
  }

  if (typeof claims !== 'object' || claims === null || Array.isArray(claims)) {
    return { ok: false, reason: 'MALFORMED' };
  }
  const c = claims as Record<string, unknown>;
  if (
    !isNonEmptyString(c.sub) ||
    typeof c.scope !== 'string' ||
    typeof c.aud !== 'string' ||
    typeof c.iss !== 'string' ||
    !isEpochSeconds(c.iat) ||
    !isEpochSeconds(c.exp) ||
    c.exp <= c.iat
  ) {
    return { ok: false, reason: 'MALFORMED' };
  }

  if (c.iss !== expected.issuer) return { ok: false, reason: 'WRONG_ISSUER' };
  if (c.aud !== expected.audience) {
    return { ok: false, reason: 'WRONG_AUDIENCE' };
  }

  const nowMs = expected.now.getTime();
  if (nowMs >= c.exp * 1000) return { ok: false, reason: 'EXPIRED' };
  if (c.iat * 1000 > nowMs) return { ok: false, reason: 'NOT_YET_VALID' };

  const scopes = expected.scopes ?? AGENT_PORTAL_SCOPES;
  if (!scopes.includes(c.scope as AgentTokenScope)) {
    return { ok: false, reason: 'BAD_SCOPE' };
  }

  return {
    ok: true,
    claims: {
      sub: c.sub,
      scope: c.scope as AgentTokenScope,
      aud: c.aud,
      iss: c.iss,
      iat: c.iat,
      exp: c.exp,
    },
  };
}
