/** In-memory fakes for the ports Shaaz will implement. Tests only. */
import { createHmac } from 'crypto';
import {
  AgentAuditEntry,
  AgentAuditPort,
  AgentIdentifierHasher,
  AgentIdentifierKind,
  AgentOtpChallenge,
  AgentOtpPort,
  AgentOtpPurpose,
  AgentOtpVerifyResult,
  AgentPermission,
  AgentPermissionDeniedError,
  AgentPermissionPort,
  AgentSettingsPort,
} from '../ports/agent-platform-ports';
import type { AgentClock } from '../ports/agent-infra-ports';

export interface FakeAgentOtpOptions {
  clock: AgentClock;
  ttlMs: number;
  maxAttempts: number;
}

interface FakeChallenge {
  phoneE164: string;
  code: string;
  expiresAt: Date;
  attempts: number;
  used: boolean;
}

export class FakeAgentOtp implements AgentOtpPort {
  private readonly challenges = new Map<string, FakeChallenge>();
  private counter = 0;

  constructor(private readonly options: FakeAgentOtpOptions) {}

  send(
    _purpose: AgentOtpPurpose,
    phoneE164: string,
  ): Promise<AgentOtpChallenge> {
    this.counter += 1;
    const challengeId = `challenge-${this.counter}`;
    // Deterministic six-digit code so tests can read it back.
    const code = String(100000 + this.counter * 7).slice(0, 6);
    const expiresAt = new Date(
      this.options.clock.now().getTime() + this.options.ttlMs,
    );
    this.challenges.set(challengeId, {
      phoneE164,
      code,
      expiresAt,
      attempts: 0,
      used: false,
    });
    return Promise.resolve({ challengeId, expiresAt });
  }

  verify(challengeId: string, code: string): Promise<AgentOtpVerifyResult> {
    const challenge = this.challenges.get(challengeId);
    if (!challenge) return Promise.resolve({ ok: false, reason: 'NOT_FOUND' });
    if (challenge.used) {
      return Promise.resolve({ ok: false, reason: 'ALREADY_USED' });
    }
    if (this.options.clock.now().getTime() >= challenge.expiresAt.getTime()) {
      return Promise.resolve({ ok: false, reason: 'EXPIRED' });
    }
    if (challenge.attempts >= this.options.maxAttempts) {
      return Promise.resolve({ ok: false, reason: 'TOO_MANY_ATTEMPTS' });
    }
    challenge.attempts += 1;
    if (code !== challenge.code) {
      return Promise.resolve({ ok: false, reason: 'INVALID_CODE' });
    }
    challenge.used = true;
    return Promise.resolve({ ok: true, phoneE164: challenge.phoneE164 });
  }

  /** Test helper: what the user would have received by SMS. */
  codeFor(challengeId: string): string {
    const challenge = this.challenges.get(challengeId);
    if (!challenge) throw new Error(`Unknown challenge ${challengeId}`);
    return challenge.code;
  }
}

export class FakeAgentSettings implements AgentSettingsPort {
  private readonly values = new Map<string, unknown>();

  constructor(initial: Record<string, unknown> = {}) {
    for (const [key, value] of Object.entries(initial)) {
      this.values.set(key, value);
    }
  }

  set(key: string, value: unknown): void {
    this.values.set(key, value);
  }

  remove(key: string): void {
    this.values.delete(key);
  }

  getMany(keys: readonly string[]): Promise<Record<string, unknown>> {
    const result: Record<string, unknown> = {};
    for (const key of keys) {
      if (this.values.has(key)) result[key] = this.values.get(key);
    }
    return Promise.resolve(result);
  }
}

export class FakeAgentIdentifierHasher implements AgentIdentifierHasher {
  constructor(private readonly secret: string) {
    if (!secret) throw new RangeError('secret must be a non-empty string.');
  }

  hash(kind: AgentIdentifierKind, value: string): string {
    if (typeof value !== 'string' || value.length === 0) {
      throw new RangeError('value must be a non-empty string.');
    }
    return createHmac('sha256', this.secret)
      .update(`${kind}:${value}`)
      .digest('hex');
  }
}

export class FakeAgentPermission implements AgentPermissionPort {
  private readonly grants = new Map<string, Map<string, Set<string>>>();

  grant(actorId: string, permission: AgentPermission): void {
    const modules = this.grants.get(actorId) ?? new Map<string, Set<string>>();
    const actions = modules.get(permission.module) ?? new Set<string>();
    actions.add(permission.action);
    modules.set(permission.module, actions);
    this.grants.set(actorId, modules);
  }

  assert(actorId: string, permission: AgentPermission): Promise<void> {
    const allowed =
      typeof actorId === 'string' &&
      actorId.length > 0 &&
      this.grants
        .get(actorId)
        ?.get(permission.module)
        ?.has(permission.action) === true;
    return allowed
      ? Promise.resolve()
      : Promise.reject(new AgentPermissionDeniedError(permission));
  }
}

export class FakeAgentAudit implements AgentAuditPort {
  private readonly stored: AgentAuditEntry[] = [];

  record(entry: AgentAuditEntry): Promise<void> {
    if (!entry.action) {
      return Promise.reject(new RangeError('action must be non-empty.'));
    }
    if (!entry.entity) {
      return Promise.reject(new RangeError('entity must be non-empty.'));
    }
    // A copy, so changing the object afterwards cannot rewrite history.
    this.stored.push(structuredClone(entry));
    return Promise.resolve();
  }

  get entries(): readonly AgentAuditEntry[] {
    return this.stored.map((entry) => structuredClone(entry));
  }
}
