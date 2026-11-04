/**
 * Issues agent and applicant sessions: the access token (through the
 * `AgentTokenSigner` port and `buildAgentAccessClaims`) and, for agents, a
 * rotating refresh token.
 *
 * Lifetimes come from the settings port on every call and are never
 * defaulted. Issuer, audience and the refresh-token pepper are parameters
 * (deployment configuration, not business settings).
 */
import { randomUUID } from 'node:crypto';
import { AgentConfigError } from '../config/agent-config.service';
import type { AgentProfile } from '../agent/agent-profile-builder';
import { AgentProfileBuilder } from '../agent/agent-profile-builder';
import type { AgentRecord } from '../ports/agent-data-ports';
import type {
  AgentRefreshTokenRecord,
  AgentRefreshTokenRepository,
} from '../ports/agent-data-ports';
import type { AgentClock, AgentTokenSigner } from '../ports/agent-infra-ports';
import type { AgentSettingsPort } from '../ports/agent-platform-ports';
import type { AgentTx } from '../ports/agent-unit-of-work.port';
import {
  AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
  AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY,
  parseAgentProgramSettings,
} from '../settings/agent-program-settings';
import { buildAgentAccessClaims } from './agent-access-claims';
import {
  generateRefreshToken,
  hashRefreshToken,
  RandomBytes,
} from './refresh-token';

export interface AgentAuthOptions {
  issuer: string;
  audience: string;
  /** Secret keying the stored hash of refresh tokens. From configuration. */
  refreshTokenPepper: string;
  /** How long a verified applicant phone is remembered for an application. */
  /**
   * Optional: when absent, the remembered phone lives exactly as long as the
   * applicant's access token (the access-token lifetime setting), so no
   * window is a constant.
   */
  applicantPhoneTtlSeconds?: number;
}

export function assertAgentAuthOptions(options: AgentAuthOptions): void {
  for (const key of ['issuer', 'audience', 'refreshTokenPepper'] as const) {
    if (typeof options[key] !== 'string' || options[key].length === 0) {
      throw new RangeError(`${key} must be a non-empty string.`);
    }
  }
  if (
    options.applicantPhoneTtlSeconds !== undefined &&
    (!Number.isSafeInteger(options.applicantPhoneTtlSeconds) ||
      options.applicantPhoneTtlSeconds < 1)
  ) {
    throw new RangeError('applicantPhoneTtlSeconds must be an integer >= 1.');
  }
}

export interface AgentLifetimes {
  accessTtlSeconds: number;
  refreshTtlSeconds: number;
}

export interface AgentSession {
  accessToken: string;
  refreshToken: string;
  expiresInSeconds: number;
  scope: 'AGENT';
  agent: AgentProfile;
}

export interface AgentApplicantSession {
  accessToken: string;
  expiresInSeconds: number;
  scope: 'APPLICANT';
}

export interface AgentSessionIssuerDeps {
  signer: AgentTokenSigner;
  clock: AgentClock;
  settings: AgentSettingsPort;
  refreshTokens: AgentRefreshTokenRepository;
  profiles: AgentProfileBuilder;
  options: AgentAuthOptions;
  /** Injectable so tests are deterministic. */
  newId?: () => string;
  randomBytes?: RandomBytes;
}

export class AgentSessionIssuer {
  private readonly newId: () => string;

  constructor(private readonly deps: AgentSessionIssuerDeps) {
    assertAgentAuthOptions(deps.options);
    this.newId = deps.newId ?? randomUUID;
  }

  /**
   * Reads both token lifetimes. Throws `AgentConfigError` listing what is not
   * set, or a RangeError naming a setting that is set wrongly.
   */
  async lifetimes(): Promise<AgentLifetimes> {
    const keys = [
      AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
      AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY,
    ];
    const parsed = parseAgentProgramSettings(
      await this.deps.settings.getMany(keys),
    );
    const missing = keys.filter((key) => parsed.missing.includes(key));
    const { accessTokenTtlSeconds, refreshTokenTtlSeconds } = parsed.settings;
    if (
      missing.length > 0 ||
      accessTokenTtlSeconds === undefined ||
      refreshTokenTtlSeconds === undefined
    ) {
      throw new AgentConfigError(missing);
    }
    return {
      accessTtlSeconds: accessTokenTtlSeconds,
      refreshTtlSeconds: refreshTokenTtlSeconds,
    };
  }

  /** An access token only: an applicant has no refresh token. */
  async issueApplicant(
    phoneHash: string,
    lifetimes: AgentLifetimes,
  ): Promise<AgentApplicantSession> {
    return {
      accessToken: await this.signAccess(
        null,
        phoneHash,
        'APPLICANT',
        lifetimes,
      ),
      expiresInSeconds: lifetimes.accessTtlSeconds,
      scope: 'APPLICANT',
    };
  }

  /**
   * An access token and a new refresh token, stored hashed. With
   * `rotateFromTokenId` the old token is revoked in the same step (a
   * concurrent second rotation throws AgentConflictError ALREADY_REVOKED).
   * Call inside the unit of work, passing its `tx`.
   */
  async issueAgent(
    agent: AgentRecord,
    tx: AgentTx,
    lifetimes: AgentLifetimes,
    rotateFromTokenId?: string,
  ): Promise<AgentSession> {
    const now = this.deps.clock.now();
    const refreshToken = generateRefreshToken(this.deps.randomBytes);
    const record: AgentRefreshTokenRecord = {
      id: this.newId(),
      agentId: agent.id,
      tokenHash: hashRefreshToken(
        refreshToken,
        this.deps.options.refreshTokenPepper,
      ),
      expiresAt: new Date(now.getTime() + lifetimes.refreshTtlSeconds * 1000),
      revokedAt: null,
      createdAt: now,
    };
    if (rotateFromTokenId === undefined) {
      await this.deps.refreshTokens.create(record, tx);
    } else {
      await this.deps.refreshTokens.rotate(rotateFromTokenId, record, now, tx);
    }
    return {
      accessToken: await this.signAccess(
        agent.id,
        agent.phoneHash,
        'AGENT',
        lifetimes,
      ),
      refreshToken,
      expiresInSeconds: lifetimes.accessTtlSeconds,
      scope: 'AGENT',
      agent: await this.deps.profiles.build(agent, tx),
    };
  }

  private signAccess(
    agentId: string | null,
    phoneHash: string,
    scope: 'AGENT' | 'APPLICANT',
    lifetimes: AgentLifetimes,
  ): Promise<string> {
    return this.deps.signer.sign(
      buildAgentAccessClaims({
        agentId,
        phoneHash,
        scope,
        now: this.deps.clock.now(),
        ttlSeconds: lifetimes.accessTtlSeconds,
        issuer: this.deps.options.issuer,
        audience: this.deps.options.audience,
      }),
    );
  }
}
