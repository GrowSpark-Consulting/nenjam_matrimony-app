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
  AgentOtpRateLimitError,
  AgentOtpVerifyResult,
  AgentPermission,
  AgentPermissionDeniedError,
  AgentPermissionPort,
  AgentSettingsPort,
} from '../ports/agent-platform-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type { AgentTx } from '../ports/agent-unit-of-work.port';
import { trackWrite } from './fake-agent-unit-of-work';

export interface FakeAgentOtpOptions {
  clock: AgentClock;
  ttlMs: number;
  maxAttempts: number;
  /** At most this many `send`s per phone and purpose in any window. */
  sendLimit: number;
  sendWindowMs: number;
}

interface FakeChallenge {
  purpose: AgentOtpPurpose;
  phoneE164: string;
  code: string;
  expiresAt: Date;
  attempts: number;
  used: boolean;
}

export class FakeAgentOtp implements AgentOtpPort {
  private readonly challenges = new Map<string, FakeChallenge>();
  /** Send times (ms) per `purpose|phone`, oldest first. */
  private readonly sends = new Map<string, number[]>();
  private counter = 0;

  constructor(private readonly options: FakeAgentOtpOptions) {}

  send(
    purpose: AgentOtpPurpose,
    phoneE164: string,
  ): Promise<AgentOtpChallenge> {
    const now = this.options.clock.now().getTime();
    const key = `${purpose}|${phoneE164}`;
    const recent = (this.sends.get(key) ?? []).filter(
      (at) => at > now - this.options.sendWindowMs,
    );
    if (recent.length >= this.options.sendLimit) {
      // The oldest send leaves the window at oldest + window.
      const retryMs = recent[0] + this.options.sendWindowMs - now;
      return Promise.reject(
        new AgentOtpRateLimitError(Math.max(1, Math.ceil(retryMs / 1000))),
      );
    }
    recent.push(now);
    this.sends.set(key, recent);

    this.counter += 1;
    const challengeId = `challenge-${this.counter}`;
    // Deterministic six-digit code so tests can read it back.
    const code = String(100000 + this.counter * 7).slice(0, 6);
    const expiresAt = new Date(now + this.options.ttlMs);
    this.challenges.set(challengeId, {
      purpose,
      phoneE164,
      code,
      expiresAt,
      attempts: 0,
      used: false,
    });
    return Promise.resolve({ challengeId, expiresAt });
  }

  verify(
    purpose: AgentOtpPurpose,
    challengeId: string,
    code: string,
  ): Promise<AgentOtpVerifyResult> {
    const challenge = this.challenges.get(challengeId);
    // Another purpose looks exactly like an unknown challenge, and does not
    // count as an attempt.
    if (!challenge || challenge.purpose !== purpose) {
      return Promise.resolve({ ok: false, reason: 'NOT_FOUND' });
    }
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

/**
 * Mimics the agreed real hasher: normalises per kind (trim; lower-case email;
 * upper-case PAN) and returns "v1:" plus a keyed hash. The phone is only
 * trimmed: E.164 is NOT validated here.
 */
export class FakeAgentIdentifierHasher implements AgentIdentifierHasher {
  /**
   * `olderSecrets` are earlier pepper versions still active during a rotation
   * (newest first, after `secret`). Their hashes are labelled "v0:", "v-1:" ...
   */
  constructor(
    private readonly secret: string,
    private readonly olderSecrets: readonly string[] = [],
  ) {
    if (!secret) throw new RangeError('secret must be a non-empty string.');
  }

  hashAll(kind: AgentIdentifierKind, value: string): string[] {
    return [
      this.hash(kind, value),
      ...this.olderSecrets.map((older, index) =>
        this.hashWith(older, `v${index === 0 ? 0 : -index}`, kind, value),
      ),
    ];
  }

  hash(kind: AgentIdentifierKind, value: string): string {
    return this.hashWith(this.secret, 'v1', kind, value);
  }

  private hashWith(
    secret: string,
    label: string,
    kind: AgentIdentifierKind,
    value: string,
  ): string {
    if (typeof value !== 'string') {
      throw new RangeError('value must be a string.');
    }
    let normalised = value.trim();
    if (kind === 'EMAIL') normalised = normalised.toLowerCase();
    if (kind === 'PAN') normalised = normalised.toUpperCase();
    if (normalised.length === 0) {
      throw new RangeError('value must not be empty.');
    }
    const digest = createHmac('sha256', secret)
      .update(`${kind}:${normalised}`)
      .digest('hex');
    return `${label}:${digest}`;
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

  /** Default-deny. The `tx` is accepted (reads see the live state). */
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

  record(entry: AgentAuditEntry, tx?: AgentTx): Promise<void> {
    if (!entry.action) {
      return Promise.reject(new RangeError('action must be non-empty.'));
    }
    if (!entry.entity) {
      return Promise.reject(new RangeError('entity must be non-empty.'));
    }
    const track = trackWrite(tx);
    // A copy, so changing the object afterwards cannot rewrite history.
    const row = structuredClone(entry);
    this.stored.push(row);
    track(() => {
      this.stored.splice(this.stored.indexOf(row), 1);
    });
    return Promise.resolve();
  }

  get entries(): readonly AgentAuditEntry[] {
    return this.stored.map((entry) => structuredClone(entry));
  }
}
