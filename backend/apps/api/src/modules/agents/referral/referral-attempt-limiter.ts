/**
 * The attempt limit shared by the member-side referral calls (check a code,
 * attach a code, quote a discount). Not wired into any module.
 *
 * `check` refuses with RATE_LIMITED, or records this attempt. The limits and
 * the window are settings (never defaulted) and are read on every call. The
 * requester key is OPAQUE (a hashed IP, or a namespaced member id), never a
 * raw IP; the attempt store refuses a raw IP too.
 *
 * LIMIT TO CLOSE IN THE REAL ADAPTER (accepted for now): counting is
 * check-then-record, so a burst of parallel requests can pass a limit by a
 * few; an atomic counter closes that.
 */
import { AgentConfigError } from '../config/agent-config.service';
import { AgentServiceError } from '../errors/agent-service-error';
import type { ReferralCodeAttemptStore } from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type { AgentSettingsPort } from '../ports/agent-platform-ports';
import {
  parseAgentProgramSettings,
  REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY,
} from '../settings/agent-program-settings';
import { decideCodeValidationAttempt } from './code-validation';

export interface ReferralAttemptLimiterDeps {
  settings: AgentSettingsPort;
  attempts: ReferralCodeAttemptStore;
  clock: AgentClock;
}

interface Limits {
  ipLimit: number;
  codeLimit: number;
  windowSeconds: number;
}

export class ReferralAttemptLimiter {
  constructor(private readonly deps: ReferralAttemptLimiterDeps) {}

  /** Refuses with RATE_LIMITED, or records this attempt. */
  async check(requesterKey: string, codeKey: string | null): Promise<void> {
    const limits = await this.limits();
    const now = this.deps.clock.now();
    const windowMs = limits.windowSeconds * 1000;
    const since = new Date(now.getTime() - windowMs);

    const requester = await this.deps.attempts.window(
      'REQUESTER',
      requesterKey,
      since,
    );
    // Text that is not a code counts against the requester only.
    const code =
      codeKey === null
        ? { count: 0, oldestAt: null }
        : await this.deps.attempts.window('CODE', codeKey, since);

    const decision = decideCodeValidationAttempt({
      ipAttempts: requester.count,
      codeAttempts: code.count,
      ipLimit: limits.ipLimit,
      codeLimit: limits.codeLimit,
    });
    if (!decision.allowed) {
      const oldest =
        decision.reason === 'IP_LIMIT' ? requester.oldestAt : code.oldestAt;
      const msLeft =
        (oldest?.getTime() ?? now.getTime()) + windowMs - now.getTime();
      throw new AgentServiceError('RATE_LIMITED', {
        retryAfterSeconds: Math.max(1, Math.ceil(msLeft / 1000)),
      });
    }
    await this.deps.attempts.record({ requesterKey, codeKey, at: now });
  }

  private async limits(): Promise<Limits> {
    const keys = [
      REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY,
      REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY,
      REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY,
    ];
    const parsed = parseAgentProgramSettings(
      await this.deps.settings.getMany(keys),
    );
    const missing = keys.filter((key) => parsed.missing.includes(key));
    const {
      codeValidationIpLimit,
      codeValidationCodeLimit,
      codeValidationWindowSeconds,
    } = parsed.settings;
    if (
      missing.length > 0 ||
      codeValidationIpLimit === undefined ||
      codeValidationCodeLimit === undefined ||
      codeValidationWindowSeconds === undefined
    ) {
      throw new AgentConfigError(missing);
    }
    return {
      ipLimit: codeValidationIpLimit,
      codeLimit: codeValidationCodeLimit,
      windowSeconds: codeValidationWindowSeconds,
    };
  }
}
