/**
 * The agent program's settings and OTP ports, backed by Shaaz's platform
 * services, plus the registration of our settings validators. Thin on
 * purpose: each one translates between our port and his API and nothing else.
 *
 * - `PlatformSettingsAdapter`: `PlatformSettingsService.getMany` (only keys
 *   that exist come back; stored JSON, unvalidated — our parser validates).
 * - `PlatformOtpAdapter`: `OtpService.send` / `verify`. His
 *   `OtpRateLimitError` becomes our `AgentOtpRateLimitError`; his RangeError
 *   (a phone that is not E.164) becomes our VALIDATION_FAILED; his 503
 *   (`OTP_DELIVERY_UNAVAILABLE`) and any other error pass through unchanged.
 * - `AgentSettingValidators`: registers one validator per agent-program key
 *   with `PlatformSettingsService.registerValidator` in `onModuleInit`, so an
 *   admin who enters a bad value is refused at entry, not at the next read.
 */
import { Injectable, type OnModuleInit } from '@nestjs/common';
import {
  OTP_POLICY,
  OtpRateLimitError,
  type OtpService,
} from '../../../platform/otp/otp.service';
import { PlatformSettingsService } from '../../../platform/settings/platform-settings.service';
import { AgentServiceError } from '../../errors/agent-service-error';
import {
  AgentOtpRateLimitError,
  type AgentAuditEntry,
  type AgentAuditPort,
  type AgentOtpChallenge,
  type AgentOtpPort,
  type AgentOtpPurpose,
  type AgentOtpVerifyResult,
  type AgentSettingsPort,
} from '../../ports/agent-platform-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import {
  AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
  AGENT_PROGRAM_SETTING_KEYS,
  agentProgramSettingProblem,
} from '../../settings/agent-program-settings';
import {
  AGENT_QUOTE_ENABLED_KEY,
  agentQuoteEnabledProblem,
} from '../../settings/agent-quote-switch';

export class PlatformSettingsAdapter implements AgentSettingsPort {
  constructor(
    private readonly settings: Pick<PlatformSettingsService, 'getMany'>,
  ) {}

  getMany(keys: readonly string[]): Promise<Record<string, unknown>> {
    return this.settings.getMany(keys);
  }
}

export class PlatformOtpAdapter implements AgentOtpPort {
  constructor(private readonly otp: Pick<OtpService, 'send' | 'verify'>) {}

  async send(
    purpose: AgentOtpPurpose,
    phoneE164: string,
  ): Promise<AgentOtpChallenge> {
    try {
      const issued = await this.otp.send(purpose, phoneE164);
      return { challengeId: issued.challengeId, expiresAt: issued.expiresAt };
    } catch (error) {
      if (error instanceof OtpRateLimitError) {
        // Ours insists on a positive integer; his is already ceil'd.
        throw new AgentOtpRateLimitError(
          Math.max(1, Math.ceil(error.retryAfterSeconds)),
        );
      }
      if (error instanceof RangeError) {
        throw new AgentServiceError('VALIDATION_FAILED', { fields: ['phone'] });
      }
      throw error;
    }
  }

  verify(
    purpose: AgentOtpPurpose,
    challengeId: string,
    code: string,
  ): Promise<AgentOtpVerifyResult> {
    return this.otp.verify(purpose, challengeId, code);
  }
}

/** The shortest resend time the OTP service itself enforces, in seconds. */
export const OTP_SERVICE_RESEND_FLOOR_SECONDS = Math.ceil(
  OTP_POLICY.resendAfterMs / 1000,
);

/**
 * The problem with [value] for agent-program key [key], or null. One extra
 * rule beyond the parser: the resend time we SHOW must not be shorter than
 * the one the OTP service enforces, or a client that waits as told gets 429.
 */
export function agentSettingValidator(
  key: string,
): (value: unknown) => string | null {
  return (value) => {
    const problem = agentProgramSettingProblem(key, value);
    if (problem) return problem;
    if (
      key === AGENT_OTP_RESEND_AFTER_SECONDS_KEY &&
      (value as number) < OTP_SERVICE_RESEND_FLOOR_SECONDS
    ) {
      return `Setting ${key} must be at least ${OTP_SERVICE_RESEND_FLOOR_SECONDS} (the sign-in code service's own resend limit).`;
    }
    return null;
  };
}

@Injectable()
export class AgentSettingValidators implements OnModuleInit {
  constructor(private readonly settings: PlatformSettingsService) {}

  onModuleInit(): void {
    for (const key of AGENT_PROGRAM_SETTING_KEYS) {
      this.settings.registerValidator(key, agentSettingValidator(key));
    }
    // The quote kill switch (not one of the seeded keys).
    this.settings.registerValidator(
      AGENT_QUOTE_ENABLED_KEY,
      agentQuoteEnabledProblem,
    );
  }
}

/**
 * The audit port for the agent-facing routes: the same writer as the admin
 * routes, but an entry with an actor is the AGENT acting (the admin adapter
 * would label it STAFF) and one without is the SYSTEM. An explicit
 * `actorType` on the entry still wins.
 */
export class AgentActorAuditAdapter implements AgentAuditPort {
  constructor(private readonly inner: AgentAuditPort) {}

  record(entry: AgentAuditEntry, tx?: AgentTx): Promise<void> {
    return this.inner.record(
      {
        ...entry,
        actorType:
          entry.actorType ?? (entry.actorId === null ? 'SYSTEM' : 'AGENT'),
      },
      tx,
    );
  }
}
