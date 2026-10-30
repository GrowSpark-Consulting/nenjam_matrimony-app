/**
 * Agent sign-in: OTP start and verify, refresh, logout.
 *
 * Depends only on ports and the pure functions in this module; not wired into
 * any module or controller yet. Everything that changes the database runs in
 * `AgentUnitOfWork.run` and passes its `tx` on.
 *
 * OTP request and verify follow docs/agent-program/agent-api.openapi.yaml:
 * `start` returns a `challengeId`, `verify` takes it with the code, and the
 * phone comes from the verified challenge.
 */
import { agentCapabilitiesFor } from '../agent/agent-status';
import { AgentServiceError } from '../errors/agent-service-error';
import { AgentConfigError } from '../config/agent-config.service';
import {
  AgentApplicantRepository,
  AgentConflictError,
  AgentRefreshTokenRepository,
  AgentRepository,
} from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import {
  AgentAuditPort,
  AgentIdentifierHasher,
  AgentOtpChallenge,
  AgentOtpPort,
  AgentOtpRateLimitError,
  AgentSettingsPort,
  AgentOtpVerifyFailure,
} from '../ports/agent-platform-ports';
import {
  AGENT_SEAL_PURPOSES,
  type AgentSecretSealer,
} from '../ports/agent-secret-sealer.port';
import type { AgentUnitOfWork } from '../ports/agent-unit-of-work.port';
import {
  AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
  parseAgentProgramSettings,
} from '../settings/agent-program-settings';
import type { AgentAccessClaims } from './agent-access-claims';
import {
  AgentApplicantSession,
  AgentAuthOptions,
  AgentSession,
  AgentSessionIssuer,
  assertAgentAuthOptions,
} from './agent-session-issuer';
import { decideRefreshToken, hashRefreshToken } from './refresh-token';

const E164 = /^\+[1-9][0-9]{7,14}$/;
const OTP_CODE = /^[0-9]{4,8}$/;

export interface AgentOtpStartResult {
  challengeId: string;
  expiresInSeconds: number;
  resendAfterSeconds: number;
}

export interface AgentSignInDeps {
  otp: AgentOtpPort;
  hasher: AgentIdentifierHasher;
  agents: AgentRepository;
  refreshTokens: AgentRefreshTokenRepository;
  applicants: AgentApplicantRepository;
  sealer: AgentSecretSealer;
  uow: AgentUnitOfWork;
  audit: AgentAuditPort;
  settings: AgentSettingsPort;
  clock: AgentClock;
  issuer: AgentSessionIssuer;
  options: AgentAuthOptions;
}

export class AgentSignInService {
  constructor(private readonly deps: AgentSignInDeps) {
    assertAgentAuthOptions(deps.options);
  }

  /**
   * Sends the sign-in OTP. It never looks the phone up, so the answer is the
   * same whether or not the phone belongs to an agent.
   */
  async start(phone: string): Promise<AgentOtpStartResult> {
    if (typeof phone !== 'string' || !E164.test(phone)) {
      throw new AgentServiceError('VALIDATION_FAILED', { fields: ['phone'] });
    }
    // Read the setting first: do not send an SMS we cannot answer properly.
    const resendAfterSeconds = await this.resendAfterSeconds();
    let challenge: AgentOtpChallenge;
    try {
      challenge = await this.deps.otp.send('AGENT_SIGN_IN', phone);
    } catch (error) {
      if (error instanceof AgentOtpRateLimitError) {
        throw new AgentServiceError('RATE_LIMITED', {
          retryAfterSeconds: error.retryAfterSeconds,
        });
      }
      throw error;
    }
    const msLeft =
      challenge.expiresAt.getTime() - this.deps.clock.now().getTime();
    return {
      challengeId: challenge.challengeId,
      expiresInSeconds: Math.max(1, Math.ceil(msLeft / 1000)),
      resendAfterSeconds,
    };
  }

  /**
   * Checks the code. A phone with no agent record gets an applicant session
   * (access token only; the verified phone is remembered, sealed, for the
   * application). A phone with an agent record, in ANY status, gets an agent
   * session with a rotating refresh token.
   */
  async verify(
    challengeId: string,
    code: string,
  ): Promise<AgentSession | AgentApplicantSession> {
    const invalid: string[] = [];
    if (typeof challengeId !== 'string' || challengeId.length === 0) {
      invalid.push('challengeId');
    }
    if (typeof code !== 'string' || !OTP_CODE.test(code)) invalid.push('code');
    if (invalid.length > 0) {
      throw new AgentServiceError('VALIDATION_FAILED', { fields: invalid });
    }

    // Before the OTP is consumed, so a missing setting cannot burn a code.
    const lifetimes = await this.deps.issuer.lifetimes();

    const result = await this.deps.otp.verify(
      'AGENT_SIGN_IN',
      challengeId,
      code,
    );
    if (!result.ok) throw otpFailure(result.reason);

    const phone = result.phoneE164;
    const phoneHash = this.deps.hasher.hash('PHONE', phone);
    return this.deps.uow.run(async (tx) => {
      const agent = await this.deps.agents.findByPhoneHash(phoneHash, tx);
      if (agent === null) {
        const now = this.deps.clock.now();
        await this.deps.applicants.save(
          {
            phoneHash,
            phoneSealed: this.deps.sealer.seal(
              AGENT_SEAL_PURPOSES.applicantPhone,
              phone,
            ),
            expiresAt: new Date(
              now.getTime() +
                (this.deps.options.applicantPhoneTtlSeconds ??
                  lifetimes.accessTtlSeconds) *
                  1000,
            ),
          },
          tx,
        );
        return this.deps.issuer.issueApplicant(phoneHash, lifetimes);
      }
      if (!agentCapabilitiesFor(agent.status).refreshSession) {
        throw new AgentServiceError('UNAUTHORIZED');
      }
      return this.deps.issuer.issueAgent(agent, tx, lifetimes);
    });
  }

  /**
   * Exchanges a refresh token for a new pair; the old one is revoked. A
   * revoked token presented again revokes EVERY token of that agent.
   */
  async refresh(refreshToken: string): Promise<AgentSession> {
    if (typeof refreshToken !== 'string' || refreshToken.length === 0) {
      throw new AgentServiceError('VALIDATION_FAILED', {
        fields: ['refreshToken'],
      });
    }
    const lifetimes = await this.deps.issuer.lifetimes();
    const now = this.deps.clock.now();
    const record = await this.deps.refreshTokens.findByHash(
      this.hash(refreshToken),
    );
    const agent =
      record === null ? null : await this.deps.agents.findById(record.agentId);

    const decision = decideRefreshToken({
      found: record !== null && agent !== null,
      revokedAt: record?.revokedAt ?? null,
      expiresAt: record?.expiresAt ?? now,
      now,
      agentStatus: agent?.status ?? '',
    });
    if (!decision.ok) {
      if (decision.reason === 'REUSED_REVOKED_TOKEN' && record !== null) {
        return this.failReuse(record.agentId);
      }
      throw refreshFailure(decision.reason);
    }
    if (record === null || agent === null) {
      throw new AgentServiceError('REFRESH_TOKEN_INVALID');
    }

    try {
      return await this.deps.uow.run((tx) =>
        this.deps.issuer.issueAgent(agent, tx, lifetimes, record.id),
      );
    } catch (error) {
      // Lost a race with another use of the same token: treat it as reuse.
      if (
        error instanceof AgentConflictError &&
        error.reason === 'ALREADY_REVOKED'
      ) {
        return this.failReuse(agent.id);
      }
      throw error;
    }
  }

  /**
   * Revokes the given refresh token, if it belongs to the signed-in agent.
   * Idempotent: an unknown, foreign or already-revoked token is not an error.
   */
  async logout(claims: AgentAccessClaims, refreshToken: string): Promise<void> {
    if (claims.scope !== 'AGENT') throw new AgentServiceError('UNAUTHORIZED');
    if (typeof refreshToken !== 'string' || refreshToken.length === 0) {
      throw new AgentServiceError('VALIDATION_FAILED', {
        fields: ['refreshToken'],
      });
    }
    const record = await this.deps.refreshTokens.findByHash(
      this.hash(refreshToken),
    );
    if (record === null || record.agentId !== claims.sub) return;
    await this.deps.uow.run(async (tx) => {
      await this.deps.refreshTokens.revoke(
        record.id,
        this.deps.clock.now(),
        tx,
      );
    });
  }

  private hash(token: string): string {
    return hashRefreshToken(token, this.deps.options.refreshTokenPepper);
  }

  /** Revokes every token of the agent (and records it), then refuses. */
  private async failReuse(agentId: string): Promise<never> {
    await this.deps.uow.run(async (tx) => {
      await this.deps.refreshTokens.revokeAllForAgent(
        agentId,
        this.deps.clock.now(),
        tx,
      );
      await this.deps.audit.record(
        {
          actorId: null,
          action: 'AGENT_REFRESH_TOKEN_REUSED',
          entity: 'agent',
          entityId: agentId,
        },
        tx,
      );
    });
    throw new AgentServiceError('REFRESH_TOKEN_REUSED');
  }

  private async resendAfterSeconds(): Promise<number> {
    const parsed = parseAgentProgramSettings(
      await this.deps.settings.getMany([AGENT_OTP_RESEND_AFTER_SECONDS_KEY]),
    );
    const value = parsed.settings.otpResendAfterSeconds;
    if (value === undefined) {
      throw new AgentConfigError([AGENT_OTP_RESEND_AFTER_SECONDS_KEY]);
    }
    return value;
  }
}

/** Nothing about a missing, used or foreign challenge is revealed. */
function otpFailure(reason: AgentOtpVerifyFailure): AgentServiceError {
  switch (reason) {
    case 'EXPIRED':
      return new AgentServiceError('OTP_EXPIRED');
    case 'TOO_MANY_ATTEMPTS':
      return new AgentServiceError('RATE_LIMITED');
    default:
      return new AgentServiceError('OTP_INVALID');
  }
}

function refreshFailure(
  reason:
    'NOT_FOUND' | 'EXPIRED' | 'AGENT_NOT_ALLOWED' | 'REUSED_REVOKED_TOKEN',
): AgentServiceError {
  return new AgentServiceError(
    reason === 'EXPIRED' ? 'REFRESH_TOKEN_EXPIRED' : 'REFRESH_TOKEN_INVALID',
  );
}
