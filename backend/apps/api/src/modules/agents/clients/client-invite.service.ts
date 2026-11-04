/**
 * Agent-added clients, the client's side (docs/agent-program/agent-api.openapi.yaml,
 * "Client invites"): POST /client-invites/otp/request and /otp/verify (no
 * token), then GET /client-invites and POST /client-invites/{id}/accept or
 * /reject with the client token.
 *
 * Every call checks the feature switch first (`agent.clients_enabled`).
 *
 * THE CLIENT TOKEN. A short-lived access token (no refresh), `scope: CLIENT`,
 * signed by its own signer with its own audience, so it is refused on every
 * agent route and an agent token is refused here. Its subject is the
 * client's phone SEALED (`agent.client_phone`), never the plain phone: the
 * service opens it to look her invitations up under every pepper version.
 * Its lifetime is the agent access-token setting.
 *
 * ACCEPT, in order:
 *  1. Checks without a transaction (unknown, closed, expired, agent not
 *     ACTIVE, already a member). A repeated accept by the same phone, after
 *     a lost response, signs her in again (idempotent).
 *  2. The Firebase account for the phone (outside the transaction; safe to
 *     retry, an orphan from a failed attempt is reused).
 *  3. One transaction: lock the invitation (and every open draft of the
 *     phone), check everything again, judge `expires_at` itself (never the
 *     daily job), create the member and her registration draft (every
 *     section the agent filled, toClientWizardDraft), credit the
 *     agent (`ADDED_BY_AGENT`, ACTIVE, the credit window from now), mark it
 *     ACCEPTED (its PII deleted), close every other open invitation for the
 *     phone, and audit.
 *  4. After the commit: her member profile (`user_profiles`) from that
 *     draft, through the member side's own `syncMatchableFromDraft`, so the
 *     member app opens the home page, not the registration wizard. It never
 *     fails the accept: `profileReady: false` says it is not there yet, and
 *     every repeat accept tries again while it is missing.
 *  5. A Firebase custom token for `signInWithCustomToken`.
 *
 * | code                     | when                                                | HTTP |
 * |--------------------------|-----------------------------------------------------|------|
 * | CLIENT_INVITES_DISABLED  | the switch is off                                   | 403  |
 * | VALIDATION_FAILED        | phone or code malformed                             | 400  |
 * | OTP_DELIVERY_UNAVAILABLE | no code can reach the phone (not a test number)     | 503  |
 * | RATE_LIMITED             | asked too often, or too many wrong codes            | 429  |
 * | OTP_INVALID / OTP_EXPIRED| the code is wrong, used, unknown / expired          | 401  |
 * | UNAUTHORIZED             | not a client token                                  | 401  |
 * | INVITE_NOT_FOUND         | no such invitation for this phone                   | 404  |
 * | INVITE_UNAVAILABLE       | expired, closed, or its agent is not ACTIVE         | 409  |
 * | ALREADY_MEMBER           | the phone has (or had) a member account             | 409  |
 */
import { randomUUID } from 'node:crypto';
import type { Logger } from '@nestjs/common';
import { toIstDate } from '../agent/ist-date';
import {
  buildAgentAccessClaims,
  type AgentAccessClaims,
} from '../auth/agent-access-claims';
import { AgentConfigError } from '../config/agent-config.service';
import { AgentServiceError } from '../errors/agent-service-error';
import type {
  AgentClientAccountPort,
  AgentClientDraftRecord,
  AgentClientMemberProfilePort,
  AgentClientDraftRepository,
  ClientPhoneProofFailure,
  ClientPhoneProofPort,
} from '../ports/agent-client-ports';
import {
  AgentConflictError,
  type AgentRepository,
  type ReferralAttributionRepository,
} from '../ports/agent-data-ports';
import type { AgentClock, AgentTokenSigner } from '../ports/agent-infra-ports';
import {
  AgentOtpRateLimitError,
  type AgentAuditPort,
  type AgentIdentifierHasher,
  type AgentSettingsPort,
} from '../ports/agent-platform-ports';
import {
  AGENT_SEAL_PURPOSES,
  type AgentSecretSealer,
} from '../ports/agent-secret-sealer.port';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';
import { splitName } from '../referral/agent-referral-code.service';
import { toDisplayName } from '../referral/agent-referral-view';
import {
  AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
  AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
  parseAgentProgramSettings,
  REFERRAL_CREDIT_WINDOW_DAYS_KEY,
  REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
} from '../settings/agent-program-settings';
import { CLIENT_DRAFT_ENTITY } from './agent-client-draft.service';
import { assertAgentClientsEnabled } from './agent-clients-enabled';
import { parseStoredClientProfile, type ClientProfile } from './client-profile';
import {
  decideClientAccept,
  effectiveClientDraftStatus,
  type ClientAcceptDecision,
} from './decide-client-draft';

const E164 = /^\+[1-9][0-9]{7,14}$/;
const OTP_CODE = /^[0-9]{4,8}$/;
const BASIS_POINTS_PER_PERCENT = 100;

export interface ClientCodeSent {
  expiresInSeconds: number;
  resendAfterSeconds: number;
}

export interface ClientSession {
  accessToken: string;
  expiresInSeconds: number;
  scope: 'CLIENT';
}

export interface ClientInviteView {
  id: string;
  /** "Ravi K." */
  agentDisplayName: string;
  /** The full profile the agent entered (wizard sections, with master-data labels). */
  details: ClientProfile;
  /** The last day she can answer, YYYY-MM-DD (IST). */
  expiresOn: string;
  referredMemberDiscountPercent: number;
}

export interface ClientAcceptResult {
  firebaseCustomToken: string;
  agentDisplayName: string;
  /** The last day the credit window covers, YYYY-MM-DD (IST). */
  windowEndsAt: string;
  /** Her member profile exists, so the app can open the home page. False: accept again. */
  profileReady: boolean;
}

export interface ClientTokenOptions {
  issuer: string;
  audience: string;
}

export interface ClientInviteServiceDeps {
  settings: AgentSettingsPort;
  proof: ClientPhoneProofPort;
  hasher: AgentIdentifierHasher;
  drafts: AgentClientDraftRepository;
  agents: Pick<AgentRepository, 'findById'>;
  attributions: Pick<
    ReferralAttributionRepository,
    'create' | 'findById' | 'isPhoneHashCredited'
  >;
  accounts: AgentClientAccountPort;
  /** Her `user_profiles` row, made after the accept has committed. */
  memberProfiles: AgentClientMemberProfilePort;
  sealer: AgentSecretSealer;
  uow: AgentUnitOfWork;
  audit: AgentAuditPort;
  clock: AgentClock;
  /** The client-token signer (its own audience, CLIENT only). */
  signer: AgentTokenSigner;
  options: ClientTokenOptions;
  /** Injectable so tests are deterministic. */
  newId?: () => string;
  logger?: Pick<Logger, 'warn'>;
}

type AcceptOutcome =
  | {
      kind: 'ACCEPTED';
      windowEndsAt: Date;
      agentName: string;
      memberId: string;
    }
  | { kind: 'LOST_RACE' }
  | Extract<ClientAcceptDecision, { kind: 'REFUSE' }>;

export class ClientInviteService {
  private readonly newId: () => string;

  constructor(private readonly deps: ClientInviteServiceDeps) {
    this.newId = deps.newId ?? randomUUID;
    for (const key of ['issuer', 'audience'] as const) {
      if (typeof deps.options[key] !== 'string' || !deps.options[key]) {
        throw new RangeError(`${key} must be a non-empty string.`);
      }
    }
  }

  /**
   * Sends a code. The answer is the same whether or not any agent added this
   * phone: nothing about invitations is looked up here.
   */
  async requestCode(phone: unknown): Promise<ClientCodeSent> {
    await assertAgentClientsEnabled(this.deps.settings);
    const e164 = requirePhone(phone);
    // Read first: do not send a code we cannot answer properly.
    const { otpResendAfterSeconds } = await this.read([
      AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
    ]);
    let sent: { expiresAt: Date };
    try {
      sent = await this.deps.proof.send(e164);
    } catch (error) {
      if (error instanceof AgentOtpRateLimitError) {
        throw new AgentServiceError('RATE_LIMITED', {
          retryAfterSeconds: error.retryAfterSeconds,
        });
      }
      throw error;
    }
    const msLeft = sent.expiresAt.getTime() - this.deps.clock.now().getTime();
    return {
      expiresInSeconds: Math.max(1, Math.ceil(msLeft / 1000)),
      resendAfterSeconds: otpResendAfterSeconds!,
    };
  }

  /** Checks the newest code sent to the phone and returns a client token. */
  async verifyCode(phone: unknown, code: unknown): Promise<ClientSession> {
    await assertAgentClientsEnabled(this.deps.settings);
    const invalid = [
      ...(typeof phone === 'string' && E164.test(phone) ? [] : ['phone']),
      ...(typeof code === 'string' && OTP_CODE.test(code) ? [] : ['code']),
    ];
    if (invalid.length > 0) {
      throw new AgentServiceError('VALIDATION_FAILED', { fields: invalid });
    }
    const e164 = phone as string;
    // Before the code is used up, so a missing setting cannot burn it.
    const { accessTokenTtlSeconds } = await this.read([
      AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
    ]);
    const result = await this.deps.proof.verify({
      kind: 'CODE',
      phoneE164: e164,
      code: code as string,
    });
    if (!result.ok) throw codeFailure(result.reason);
    const claims = buildAgentAccessClaims({
      agentId: null,
      phoneHash: '',
      clientRef: this.deps.sealer.seal(
        AGENT_SEAL_PURPOSES.clientPhone,
        result.phoneE164,
      ),
      scope: 'CLIENT',
      now: this.deps.clock.now(),
      ttlSeconds: accessTokenTtlSeconds!,
      issuer: this.deps.options.issuer,
      audience: this.deps.options.audience,
    });
    return {
      accessToken: await this.deps.signer.sign(claims),
      expiresInSeconds: accessTokenTtlSeconds!,
      scope: 'CLIENT',
    };
  }

  /** The waiting invitations for her phone, from ACTIVE agents, not run out. */
  async listInvites(
    claims: AgentAccessClaims,
  ): Promise<{ items: ClientInviteView[] }> {
    await assertAgentClientsEnabled(this.deps.settings);
    const phone = this.phoneOf(claims);
    const { referralMemberDiscountBps } = await this.read([
      REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
    ]);
    const rows = await this.deps.drafts.listWaitingForHashes(
      this.deps.hasher.hashAll('PHONE', phone),
      this.deps.clock.now(),
    );
    const items: ClientInviteView[] = [];
    for (const row of rows) {
      const agent = await this.deps.agents.findById(row.agentId);
      if (agent?.status !== 'ACTIVE' || row.detailsSealed === null) continue;
      items.push({
        id: row.id,
        agentDisplayName: agentDisplayName(agent.name),
        details: this.detailsOf(row),
        expiresOn: toIstDate(row.expiresAt),
        referredMemberDiscountPercent:
          referralMemberDiscountBps! / BASIS_POINTS_PER_PERCENT,
      });
    }
    return { items };
  }

  async accept(
    claims: AgentAccessClaims,
    id: string,
  ): Promise<ClientAcceptResult> {
    await assertAgentClientsEnabled(this.deps.settings);
    const phone = this.phoneOf(claims);
    const hashes = this.deps.hasher.hashAll('PHONE', phone);
    const { referralCreditWindowDays } = await this.read([
      REFERRAL_CREDIT_WINDOW_DAYS_KEY,
    ]);
    const creditWindowDays = referralCreditWindowDays!;
    const now = this.deps.clock.now();
    const { drafts, accounts, agents } = this.deps;

    const row = await drafts.findForPhone(id, hashes);
    if (row === null) throw new AgentServiceError('INVITE_NOT_FOUND');
    const agent = await agents.findById(row.agentId);
    const first = decideClientAccept({
      status: row.status,
      expiresAt: row.expiresAt,
      now,
      agentStatus: agent?.status ?? '',
      acceptedMemberExists:
        row.memberId !== null &&
        (await accounts.findMemberById(row.memberId)) !== null,
      phoneIsMember: (await accounts.findMemberByPhone(phone)) !== null,
      phoneCredited: await this.isCredited(hashes),
      creditWindowDays,
    });
    if (first.kind === 'REPEAT') return this.signInAgain(row);
    if (first.kind === 'REFUSE') {
      if (first.reason === 'ALREADY_MEMBER') {
        // Read just before another accept of this invitation by this phone
        // committed: the "member" is the account that accept made. Sign her
        // in, as for any repeat.
        const again = await drafts.findForPhone(id, hashes);
        if (again !== null && (await this.acceptedByThisPhone(again))) {
          return this.signInAgain(again);
        }
        await this.deps.uow.run((tx) => this.closeAsMember(row.id, now, tx));
      }
      throw refusal(first.reason);
    }

    const { uid } = await accounts.ensureFirebaseUser(phone);
    let outcome: AcceptOutcome;
    try {
      outcome = await this.deps.uow.run((tx) =>
        this.acceptInTransaction(
          { id, phone, hashes, uid, now, creditWindowDays },
          tx,
        ),
      );
    } catch (error) {
      // Her phone (or this Firebase account) got a member row meanwhile.
      if (
        error instanceof AgentConflictError &&
        (error.reason === 'DUPLICATE_MEMBER_PHONE' ||
          error.reason === 'DUPLICATE_ATTRIBUTION')
      ) {
        throw new AgentServiceError('ALREADY_MEMBER');
      }
      throw error;
    }
    if (outcome.kind === 'LOST_RACE') {
      // Someone answered first: if it was this phone accepting, sign in again.
      const again = await drafts.findForPhone(id, hashes);
      if (again !== null && (await this.acceptedByThisPhone(again))) {
        return this.signInAgain(again);
      }
      throw new AgentServiceError('INVITE_UNAVAILABLE');
    }
    if (outcome.kind === 'REFUSE') throw refusal(outcome.reason);
    const profileReady = await this.ensureMemberProfile(outcome.memberId, id);
    return {
      firebaseCustomToken: await accounts.mintSessionToken(uid),
      agentDisplayName: agentDisplayName(outcome.agentName),
      windowEndsAt: toIstDate(outcome.windowEndsAt),
      profileReady,
    };
  }

  /** Rejecting again what this phone already rejected answers the same. */
  async reject(claims: AgentAccessClaims, id: string): Promise<void> {
    await assertAgentClientsEnabled(this.deps.settings);
    const phone = this.phoneOf(claims);
    const hashes = this.deps.hasher.hashAll('PHONE', phone);
    const now = this.deps.clock.now();
    const row = await this.deps.drafts.findForPhone(id, hashes);
    if (row === null) throw new AgentServiceError('INVITE_NOT_FOUND');
    if (row.status === 'REJECTED') return;
    if (effectiveClientDraftStatus(row, now) !== 'WAITING_FOR_CLIENT') {
      throw new AgentServiceError('INVITE_UNAVAILABLE');
    }
    const rejected = await this.deps.uow.run(async (tx) => {
      const done = await this.deps.drafts.markRejected(id, hashes, now, tx);
      if (done === null) return false;
      await this.deps.audit.record(
        {
          // She has no account: a member acting, with no id.
          actorId: null,
          actorType: 'MEMBER',
          action: 'AGENT_CLIENT_INVITE_REJECTED',
          entity: CLIENT_DRAFT_ENTITY,
          entityId: id,
        },
        tx,
      );
      return true;
    });
    if (rejected) return;
    const again = await this.deps.drafts.findForPhone(id, hashes);
    if (again?.status === 'REJECTED') return;
    throw new AgentServiceError('INVITE_UNAVAILABLE');
  }

  private async acceptInTransaction(
    input: {
      id: string;
      phone: string;
      hashes: string[];
      uid: string;
      now: Date;
      creditWindowDays: number;
    },
    tx: AgentTx,
  ): Promise<AcceptOutcome> {
    const { drafts, accounts, agents, attributions, audit } = this.deps;
    const { id, phone, hashes, now } = input;
    const locked = await drafts.lockWaitingForAccept(id, hashes, now, tx);
    if (locked === null) return { kind: 'LOST_RACE' };
    const agent = await agents.findById(locked.agentId, tx);
    // Everything again, under the lock; the expiry is judged here too.
    const decision = decideClientAccept({
      status: locked.status,
      expiresAt: locked.expiresAt,
      now,
      agentStatus: agent?.status ?? '',
      acceptedMemberExists: false,
      phoneIsMember: (await accounts.findMemberByPhone(phone, tx)) !== null,
      phoneCredited: await this.isCredited(hashes, tx),
      creditWindowDays: input.creditWindowDays,
    });
    if (decision.kind === 'REFUSE') {
      if (decision.reason === 'ALREADY_MEMBER') {
        await this.closeAsMember(id, now, tx);
      }
      return decision;
    }
    if (decision.kind !== 'ACCEPT' || agent === null) {
      return { kind: 'REFUSE', reason: 'UNAVAILABLE' };
    }

    const { memberId } = await accounts.createMember(
      {
        uid: input.uid,
        phoneE164: phone,
        profile: this.detailsOf(locked),
      },
      tx,
    );
    const attribution = await attributions.create(
      {
        id: this.newId(),
        memberId,
        agentId: agent.id,
        codeId: null,
        source: 'ADDED_BY_AGENT',
        // Written under the newest pepper, after every version was checked.
        memberPhoneHash: hashes[0],
        attributedAt: now,
        status: 'ACTIVE',
        windowEndsAt: decision.windowEndsAt,
        needsReview: false,
      },
      tx,
    );
    await drafts.markAccepted(
      id,
      { memberId, attributionId: attribution.id, acceptedAt: now },
      tx,
    );
    const closed = await drafts.closeOthersForPhone(
      hashes,
      id,
      'CLIENT_ACCEPTED_ANOTHER',
      now,
      tx,
    );
    await audit.record(
      {
        actorId: memberId,
        actorType: 'MEMBER',
        action: 'AGENT_CLIENT_INVITE_ACCEPTED',
        entity: CLIENT_DRAFT_ENTITY,
        entityId: id,
      },
      tx,
    );
    await audit.record(
      {
        actorId: null,
        action: 'AGENT_ATTRIBUTION_CREATED',
        entity: 'attribution',
        entityId: attribution.id,
        metadata: { source: 'ADDED_BY_AGENT', needsReview: false },
      },
      tx,
    );
    for (const otherId of closed) {
      await audit.record(
        {
          actorId: null,
          action: 'AGENT_CLIENT_INVITE_CLOSED',
          entity: CLIENT_DRAFT_ENTITY,
          entityId: otherId,
          metadata: { reason: 'CLIENT_ACCEPTED_ANOTHER' },
        },
        tx,
      );
    }
    return {
      kind: 'ACCEPTED',
      windowEndsAt: decision.windowEndsAt,
      agentName: agent.name,
      memberId,
    };
  }

  /** The phone already has an account: this invitation can never be accepted. */
  private async closeAsMember(id: string, now: Date, tx: AgentTx) {
    if (await this.deps.drafts.close(id, 'CLIENT_ALREADY_MEMBER', now, tx)) {
      await this.deps.audit.record(
        {
          actorId: null,
          action: 'AGENT_CLIENT_INVITE_CLOSED',
          entity: CLIENT_DRAFT_ENTITY,
          entityId: id,
          metadata: { reason: 'CLIENT_ALREADY_MEMBER' },
        },
        tx,
      );
    }
  }

  /** This invitation was accepted by this phone, and her account is still there. */
  private async acceptedByThisPhone(
    row: AgentClientDraftRecord,
  ): Promise<boolean> {
    return (
      row.status === 'ACCEPTED' &&
      row.memberId !== null &&
      (await this.deps.accounts.findMemberById(row.memberId)) !== null
    );
  }

  /**
   * A repeated accept by the same phone: a fresh custom token, nothing
   * written about the invitation; her member profile is made if it is
   * still missing.
   */
  private async signInAgain(
    row: AgentClientDraftRecord,
  ): Promise<ClientAcceptResult> {
    const member =
      row.memberId === null
        ? null
        : await this.deps.accounts.findMemberById(row.memberId);
    const attribution =
      row.attributionId === null
        ? null
        : await this.deps.attributions.findById(row.attributionId);
    const agent = await this.deps.agents.findById(row.agentId);
    if (member?.firebaseUid == null || attribution === null || agent === null) {
      throw new AgentServiceError('INVITE_UNAVAILABLE');
    }
    const profileReady = await this.ensureMemberProfile(
      member.memberId,
      row.id,
    );
    return {
      firebaseCustomToken: await this.deps.accounts.mintSessionToken(
        member.firebaseUid,
      ),
      agentDisplayName: agentDisplayName(agent.name),
      windowEndsAt: toIstDate(attribution.windowEndsAt),
      profileReady,
    };
  }

  /**
   * Her member profile, made from her registration draft when it is not
   * there yet. Never throws: the accept has already committed, so a failure
   * is logged (the draft id and the kind of failure, nothing about her) and
   * answered as `profileReady: false`; the next accept tries again.
   */
  private async ensureMemberProfile(
    memberId: string,
    draftId: string,
  ): Promise<boolean> {
    const { memberProfiles } = this.deps;
    try {
      if (await memberProfiles.exists(memberId)) return true;
      await memberProfiles.createFromDraft(memberId);
      if (await memberProfiles.exists(memberId)) return true;
      this.deps.logger?.warn(
        `No member profile was made for accepted client draft ${draftId} (her draft lacks what a profile needs); the next accept tries again.`,
      );
    } catch (error) {
      this.deps.logger?.warn(
        `No member profile was made for accepted client draft ${draftId} (${(error as Error).name}); the next accept tries again.`,
      );
    }
    return false;
  }

  private async isCredited(hashes: readonly string[], tx?: AgentTx) {
    for (const hash of hashes) {
      if (await this.deps.attributions.isPhoneHashCredited(hash, tx)) {
        return true;
      }
    }
    return false;
  }

  /** The verified phone inside a client token; anything else is UNAUTHORIZED. */
  private phoneOf(claims: AgentAccessClaims): string {
    if (claims?.scope !== 'CLIENT') throw new AgentServiceError('UNAUTHORIZED');
    let phone: string;
    try {
      phone = this.deps.sealer.open(
        AGENT_SEAL_PURPOSES.clientPhone,
        claims.sub,
      );
    } catch {
      throw new AgentServiceError('UNAUTHORIZED');
    }
    if (!E164.test(phone)) throw new AgentServiceError('UNAUTHORIZED');
    return phone;
  }

  private detailsOf(row: AgentClientDraftRecord): ClientProfile {
    return parseStoredClientProfile(
      this.deps.sealer.open(
        AGENT_SEAL_PURPOSES.clientDetails,
        row.detailsSealed ?? '',
      ),
    );
  }

  /** The given settings, every one required (a 503 naming the missing keys). */
  private async read(keys: string[]) {
    const raw = await this.deps.settings.getMany(keys);
    const { settings } = parseAgentProgramSettings(raw);
    const fieldOf: Record<string, unknown> = {
      [AGENT_OTP_RESEND_AFTER_SECONDS_KEY]: settings.otpResendAfterSeconds,
      [AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY]: settings.accessTokenTtlSeconds,
      [REFERRAL_CREDIT_WINDOW_DAYS_KEY]: settings.referralCreditWindowDays,
      [REFERRAL_MEMBER_DISCOUNT_BPS_KEY]: settings.referralMemberDiscountBps,
    };
    const missing = keys.filter((key) => fieldOf[key] === undefined);
    if (missing.length > 0) throw new AgentConfigError(missing);
    return settings;
  }
}

function requirePhone(phone: unknown): string {
  if (typeof phone !== 'string' || !E164.test(phone)) {
    throw new AgentServiceError('VALIDATION_FAILED', { fields: ['phone'] });
  }
  return phone;
}

/** "Ravi Kumar" -> "Ravi K.". */
function agentDisplayName(name: string): string {
  const { first, last } = splitName(name);
  return toDisplayName(first ?? '', last);
}

function codeFailure(reason: ClientPhoneProofFailure): AgentServiceError {
  switch (reason) {
    case 'EXPIRED':
      return new AgentServiceError('OTP_EXPIRED');
    case 'TOO_MANY_ATTEMPTS':
      return new AgentServiceError('RATE_LIMITED');
    case 'UNSUPPORTED':
      return new AgentServiceError('VALIDATION_FAILED', { fields: ['code'] });
    default:
      return new AgentServiceError('OTP_INVALID');
  }
}

function refusal(reason: 'UNAVAILABLE' | 'ALREADY_MEMBER'): AgentServiceError {
  return new AgentServiceError(
    reason === 'ALREADY_MEMBER' ? 'ALREADY_MEMBER' : 'INVITE_UNAVAILABLE',
  );
}
