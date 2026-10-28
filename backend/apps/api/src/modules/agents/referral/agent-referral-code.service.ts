/**
 * Referral codes on the member side: checking a code before sign-up
 * (POST /referrals/codes/validate, no token) and attaching it after sign-in
 * (POST /registration/referral-code, member token).
 *
 * Not wired into any module or controller yet. The database changes of an
 * attach run in `AgentUnitOfWork.run`; the audit entry shares its `tx`.
 *
 * Both calls are attempt-limited. The limits and the window are settings
 * (never defaulted): the public check counts attempts per IP and per code;
 * the attach counts them per member and per code, using the same limits.
 *
 * LIMITS TO CLOSE IN THE REAL ADAPTER (accepted for now):
 *  - Counting is check-then-record, so a burst of parallel requests can pass a
 *    limit by a few; an atomic counter closes that.
 *  - `validateCode` is not constant-time: an existing code does a second
 *    lookup, so response timing could still hint at it. The rate limit is the
 *    protection until that is tightened.
 *
 * The requester key is OPAQUE. The caller hashes the IP (with Shaaz's hasher,
 * once it has an IP kind) and passes the hash; a raw IP is refused here, and
 * the attempt store refuses it too.
 *
 * PROPOSED HTTP MAPPING (to be confirmed). `AgentServiceError.code` is the
 * left-hand column.
 *
 * | code                | when                                                  | HTTP | contract `code`                |
 * |---------------------|-------------------------------------------------------|------|--------------------------------|
 * | RATE_LIMITED        | too many attempts (carries retryAfterSeconds)         | 429  | RATE_LIMITED, Retry-After      |
 * | VALIDATION_FAILED   | attach: the code is not a well-formed code            | 400  | VALIDATION_FAILED              |
 * | UNAUTHORIZED        | attach: the member is unknown                         | 401  | UNAUTHORIZED                   |
 * | CODE_NOT_FOUND      | unknown code, inactive code, or agent not ACTIVE      | 404  | CODE_NOT_FOUND                 |
 * | ALREADY_ATTRIBUTED  | member (or their phone) is already credited           | 409  | ALREADY_ATTRIBUTED             |
 * | SELF_REFERRAL       | the code belongs to the member's own phone            | 422  | SELF_REFERRAL                  |
 * | ALREADY_PAID        | the member has already paid for a plan                | 422  | ALREADY_PAID (new code)        |
 * | PHONE_NOT_VERIFIED  | no verified phone, and the source is not payment      | 422  | PHONE_NOT_VERIFIED (new code)  |
 *
 * The validate call never refuses with anything but RATE_LIMITED: every
 * invalid code, whatever the reason, is the same `{ valid: false }`.
 */
import { randomUUID } from 'node:crypto';
import { toIstDate } from '../agent/ist-date';
import { AgentConfigError } from '../config/agent-config.service';
import { AgentServiceError } from '../errors/agent-service-error';
import {
  AgentConflictError,
  AgentMemberReadPort,
  AgentRepository,
  ReferralAttributionRepository,
  ReferralCodeAttemptStore,
  ReferralCodeRepository,
} from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type {
  AgentAuditPort,
  AgentSettingsPort,
} from '../ports/agent-platform-ports';
import type { AgentUnitOfWork } from '../ports/agent-unit-of-work.port';
import {
  parseAgentProgramSettings,
  REFERRAL_CREDIT_WINDOW_DAYS_KEY,
} from '../settings/agent-program-settings';
import { toDisplayName } from './agent-referral-view';
import {
  AttributionRejectReason,
  AttributionSource,
  decideAttribution,
} from './decide-attribution';
import { toValidateResponse, ValidateResponse } from './code-validation';
import { normalizeReferralCode } from './normalize-referral-code';
import { looksLikeRawIp } from './requester-key';
import { ReferralAttemptLimiter } from './referral-attempt-limiter';

/** An opaque key is a short hash, not free text. */
const MAX_REQUESTER_KEY_LENGTH = 200;

export interface AgentAttachResult {
  attached: true;
  /** "Ravi K." */
  agentDisplayName: string;
  /** The last day the credit window covers, as an Indian date. */
  windowEndsAt: string;
}

export interface AgentReferralCodeServiceDeps {
  settings: AgentSettingsPort;
  attempts: ReferralCodeAttemptStore;
  codes: ReferralCodeRepository;
  agents: AgentRepository;
  attributions: ReferralAttributionRepository;
  members: AgentMemberReadPort;
  uow: AgentUnitOfWork;
  audit: AgentAuditPort;
  clock: AgentClock;
  /** Injectable so tests are deterministic. */
  newId?: () => string;
}

type AttachOutcome =
  | { ok: true; agentName: string; windowEndsAt: Date }
  | { ok: false; reason: AttributionRejectReason };

export class AgentReferralCodeService {
  private readonly newId: () => string;
  private readonly limiter: ReferralAttemptLimiter;

  constructor(private readonly deps: AgentReferralCodeServiceDeps) {
    this.newId = deps.newId ?? randomUUID;
    this.limiter = new ReferralAttemptLimiter(deps);
  }

  /**
   * The public check. `requesterKey` identifies the caller for rate limiting
   * and MUST be opaque: a keyed hash of the caller's IP address made by the
   * caller of this service, never the address itself (an IP is personal data).
   * A raw IP address is refused with a RangeError. Any code that is not an
   * ACTIVE agent's active code gets the same answer.
   */
  async validateCode(
    rawCode: unknown,
    requesterKey: string,
  ): Promise<ValidateResponse> {
    if (
      typeof requesterKey !== 'string' ||
      requesterKey.length === 0 ||
      requesterKey.length > MAX_REQUESTER_KEY_LENGTH
    ) {
      throw new RangeError('requesterKey must be a short non-empty string.');
    }
    if (looksLikeRawIp(requesterKey)) {
      throw new RangeError(
        'requesterKey must be a hashed key, not a raw IP address.',
      );
    }
    const code = normalizeReferralCode(rawCode);
    await this.limiter.check(`requester:${requesterKey}`, code);

    const record =
      code === null ? null : await this.deps.codes.findByCode(code);
    const agent =
      record === null ? null : await this.deps.agents.findById(record.agentId);
    const name = splitName(agent?.name);
    return toValidateResponse({
      found: record !== null && agent !== null,
      codeActive: record?.isActive ?? false,
      agentStatus: agent?.status ?? null,
      firstName: name.first,
      lastName: name.last,
    });
  }

  /**
   * Credits the signed-in member to the code's agent. The first attribution
   * wins and is never replaced; an agent's own phone is refused.
   */
  async attachCode(
    memberId: string,
    rawCode: unknown,
    source: AttributionSource = 'CODE_AT_SIGNUP',
  ): Promise<AgentAttachResult> {
    const code = normalizeReferralCode(rawCode);
    if (code === null) {
      throw new AgentServiceError('VALIDATION_FAILED', { fields: ['code'] });
    }
    await this.limiter.check(`user:${memberId}`, code);
    const creditWindowDays = await this.creditWindowDays();

    let outcome: AttachOutcome;
    try {
      outcome = await this.deps.uow.run((tx) =>
        this.attachInTransaction(
          { memberId, code, source, creditWindowDays },
          tx,
        ),
      );
    } catch (error) {
      // Two attaches for one member at once: the database kept the first.
      if (
        error instanceof AgentConflictError &&
        error.reason === 'DUPLICATE_ATTRIBUTION'
      ) {
        throw new AgentServiceError('ALREADY_ATTRIBUTED');
      }
      throw error;
    }

    if (!outcome.ok) throw refusal(outcome.reason);
    const name = splitName(outcome.agentName);
    return {
      attached: true,
      agentDisplayName: toDisplayName(name.first ?? '', name.last),
      windowEndsAt: toIstDate(outcome.windowEndsAt),
    };
  }

  private async attachInTransaction(
    input: {
      memberId: string;
      code: string;
      source: AttributionSource;
      creditWindowDays: number;
    },
    tx: Parameters<Parameters<AgentUnitOfWork['run']>[0]>[0],
  ): Promise<AttachOutcome> {
    const { members, codes, agents, attributions, audit, clock } = this.deps;
    const now = clock.now();

    const member = await members.getMember(input.memberId, tx);
    if (member === null) throw new AgentServiceError('UNAUTHORIZED');

    const record = await codes.findByCode(input.code, tx);
    const agent =
      record === null ? null : await agents.findById(record.agentId, tx);
    const existing = await attributions.findByMemberId(input.memberId, tx);
    const phoneCredited =
      member.phoneHash === null
        ? false
        : await attributions.isPhoneHashCredited(member.phoneHash, tx);

    const decision = decideAttribution({
      source: input.source,
      codeFound: record !== null && agent !== null,
      codeActive: record?.isActive ?? false,
      agentStatus: agent?.status ?? '',
      memberPhoneHash: member.phoneHash,
      agentPhoneHash: agent?.phoneHash ?? null,
      memberAlreadyAttributed: existing !== null,
      phoneAlreadyCredited: phoneCredited,
      memberHasPaid: member.hasPaid,
      now,
      creditWindowDays: input.creditWindowDays,
    });

    if (!decision.ok) {
      // A self-referral is kept for review, unless the member already has a
      // row (one per member) or their phone is already credited.
      if (
        decision.markRejected === true &&
        record !== null &&
        agent !== null &&
        existing === null &&
        !phoneCredited
      ) {
        const rejected = await attributions.create(
          {
            id: this.newId(),
            memberId: input.memberId,
            agentId: agent.id,
            codeId: record.id,
            source: input.source,
            memberPhoneHash: member.phoneHash,
            attributedAt: now,
            status: 'REJECTED',
            windowEndsAt: now,
            needsReview: false,
          },
          tx,
        );
        await audit.record(
          {
            actorId: null,
            action: 'AGENT_ATTRIBUTION_REJECTED',
            entity: 'attribution',
            entityId: rejected.id,
            metadata: { reason: decision.reason },
          },
          tx,
        );
      }
      return { ok: false, reason: decision.reason };
    }

    // The checks above guarantee both exist.
    if (record === null || agent === null) {
      return { ok: false, reason: 'INVALID_CODE' };
    }
    const created = await attributions.create(
      {
        id: this.newId(),
        memberId: input.memberId,
        agentId: agent.id,
        codeId: record.id,
        source: input.source,
        memberPhoneHash: member.phoneHash,
        attributedAt: now,
        status: 'ACTIVE',
        windowEndsAt: decision.windowEndsAt,
        needsReview: decision.needsReview === true,
      },
      tx,
    );
    await audit.record(
      {
        actorId: null,
        action: 'AGENT_ATTRIBUTION_CREATED',
        entity: 'attribution',
        entityId: created.id,
        metadata: {
          source: input.source,
          needsReview: decision.needsReview === true,
        },
      },
      tx,
    );
    return {
      ok: true,
      agentName: agent.name,
      windowEndsAt: decision.windowEndsAt,
    };
  }

  private async creditWindowDays(): Promise<number> {
    const parsed = parseAgentProgramSettings(
      await this.deps.settings.getMany([REFERRAL_CREDIT_WINDOW_DAYS_KEY]),
    );
    const days = parsed.settings.referralCreditWindowDays;
    if (days === undefined) {
      throw new AgentConfigError([REFERRAL_CREDIT_WINDOW_DAYS_KEY]);
    }
    return days;
  }
}

/** Every reason a code cannot be used looks the same to the member. */
function refusal(reason: AttributionRejectReason): AgentServiceError {
  switch (reason) {
    case 'INVALID_CODE':
    case 'CODE_INACTIVE':
    case 'AGENT_NOT_ACTIVE':
      return new AgentServiceError('CODE_NOT_FOUND');
    case 'ALREADY_ATTRIBUTED':
    case 'PHONE_ALREADY_CREDITED':
      return new AgentServiceError('ALREADY_ATTRIBUTED');
    case 'SELF_REFERRAL':
      return new AgentServiceError('SELF_REFERRAL');
    case 'ALREADY_PAID':
      return new AgentServiceError('ALREADY_PAID');
    case 'PHONE_NOT_VERIFIED':
      return new AgentServiceError('PHONE_NOT_VERIFIED');
  }
}

/** "Ravi Kumar Singh" -> first "Ravi", last "Singh"; a single name has no last. */
export function splitName(name: string | undefined | null): {
  first: string | null;
  last: string | null;
} {
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return { first: null, last: null };
  return {
    first: parts[0],
    last: parts.length > 1 ? parts[parts.length - 1] : null,
  };
}
