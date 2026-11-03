/**
 * Agent-added clients, the agent's side (docs/agent-program/agent-api.openapi.yaml,
 * "Clients"): POST/GET /agent/clients, GET/PATCH/DELETE /agent/clients/{id},
 * POST /agent/clients/{id}/submit.
 *
 * Every call checks the feature switch first (`agent.clients_enabled`, OFF
 * unless exactly true), then the agent's status: adding, editing,
 * discarding and submitting need ACTIVE (`addMembers`), reading needs
 * ACTIVE or SUSPENDED (`viewReferrals`). Every read and write is scoped to
 * the caller's own drafts in the repository query.
 *
 * THE PROFILE. The full profile of plan section 7.1 and the partner
 * preferences, in the member wizard's own sections and values
 * (`client-profile.ts`). A draft may be saved with any field missing; SUBMIT
 * needs the fields of CLIENT_PROFILE_REQUIRED_AT_SUBMIT (one list, in
 * `client-profile-required.ts`). Master-data codes are checked, and their
 * labels filled in, by `ClientReferenceDataPort`. Creating a draft needs
 * `consentConfirmed: true` (the agent confirms the client or family agreed);
 * only that it was confirmed is kept, in the audit row.
 *
 * PII. The client's phone and details are stored sealed (`agent.client_phone`,
 * `agent.client_details`); the agent only ever sees the masked phone, and the
 * details only while the draft is open. Phones are looked up under every
 * active pepper version (`hashAll`) and written under the newest (`hash`).
 * No phone, name or code is ever put in a log line, an audit row or an
 * error message; a refused phone is audited with an internal reason only.
 *
 * THE LIMIT. `agent.client_draft_limit` open drafts per agent. The count and
 * the insert run in one transaction that first locks the agent's row, so two
 * creates at once are counted one after the other and the limit cannot be
 * passed. Overdue drafts of the agent are closed in that transaction first
 * (they no longer hold a slot or the phone).
 *
 * | code                        | when                                              | HTTP |
 * |-----------------------------|---------------------------------------------------|------|
 * | CLIENT_INVITES_DISABLED     | the switch is off                                 | 403  |
 * | AGENT_NOT_ACTIVE            | the agent's status does not allow it              | 403  |
 * | VALIDATION_FAILED           | phone, consentConfirmed or details (fields named) | 400  |
 * | CLIENT_PROFILE_INCOMPLETE   | submit: a required field is empty (missingFields) | 422  |
 * | OTP_DELIVERY_UNAVAILABLE    | no code can reach the phone (not a test number)   | 503  |
 * | CLIENT_DRAFT_EXISTS         | this agent already has an open draft for it       | 409  |
 * | CLIENT_DRAFT_LIMIT_REACHED  | at the limit of open drafts                       | 422  |
 * | CLIENT_PHONE_UNAVAILABLE    | member, credited, own phone or rejected before    | 422  |
 * | CLIENT_DRAFT_NOT_FOUND      | unknown, or another agent's                       | 404  |
 * | CLIENT_DRAFT_LOCKED         | no longer a DRAFT (submitted, closed or overdue)  | 409  |
 */
import { randomUUID } from 'node:crypto';
import type { Logger } from '@nestjs/common';
import type { AgentMeService } from '../agent/agent-me.service';
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import { AgentConfigError } from '../config/agent-config.service';
import { AgentServiceError } from '../errors/agent-service-error';
import type {
  AgentClientAccountPort,
  AgentClientDraftRecord,
  AgentClientDraftRepository,
  ClientDraftPageCursor,
  ClientDraftStatus,
  ClientPhoneProofPort,
  ClientReferenceDataPort,
} from '../ports/agent-client-ports';
import { CLIENT_DRAFT_STATUSES } from '../ports/agent-client-ports';
import type { AgentContentPort } from '../ports/agent-content.port';
import {
  AgentConflictError,
  type AgentRecord,
  type ReferralAttributionRepository,
} from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type {
  AgentAuditPort,
  AgentIdentifierHasher,
  AgentSettingsPort,
} from '../ports/agent-platform-ports';
import {
  AGENT_SEAL_PURPOSES,
  type AgentSecretSealer,
} from '../ports/agent-secret-sealer.port';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';
import { maskPhone, toDisplayName } from '../referral/agent-referral-view';
import {
  AGENT_CLIENT_DRAFT_EXPIRY_DAYS_KEY,
  AGENT_CLIENT_DRAFT_LIMIT_KEY,
  parseAgentProgramSettings,
} from '../settings/agent-program-settings';
import { assertAgentClientsEnabled } from './agent-clients-enabled';
import {
  missingRequiredClientFields,
  parseStoredClientProfile,
  validateClientProfile,
  type ClientProfile,
} from './client-profile';
import { clientDraftView, type ClientDraftView } from './client-draft-view';
import {
  clientDraftExpiresAt,
  decideClientDraftCreate,
  decideClientDraftSubmit,
  effectiveClientDraftStatus,
  type ClientDraftDecision,
  type ClientPhoneFacts,
} from './decide-client-draft';

const E164 = /^\+[1-9][0-9]{7,14}$/;

export const DEFAULT_CLIENTS_PAGE_LIMIT = 20;
export const MAX_CLIENTS_PAGE_LIMIT = 50;

/**
 * How many overdue drafts one page of a close reads. A page size, not a
 * limit: the close keeps paging until none are left. The ONE place it is
 * set (the daily expiry uses it too).
 */
export const AGENT_CLIENT_EXPIRY_BATCH_SIZE = 500;

export const CLIENT_DRAFT_ENTITY = 'agent_client_draft';

export interface AgentClientDraftInput {
  /** Must be exactly true: the client or the family agreed to be added. */
  consentConfirmed?: unknown;
  phone?: unknown;
  details?: unknown;
}

export interface AgentClientsQuery {
  status?: string;
  cursor?: string;
  limit?: number;
}

export interface AgentClientsPage {
  items: ClientDraftView[];
  nextCursor: string | null;
}

export interface AgentClientDraftServiceDeps {
  access: Pick<AgentMeService, 'assertCan'>;
  drafts: AgentClientDraftRepository;
  attributions: Pick<ReferralAttributionRepository, 'isPhoneHashCredited'>;
  accounts: Pick<AgentClientAccountPort, 'findMemberByPhone'>;
  proof: Pick<ClientPhoneProofPort, 'canReach' | 'send'>;
  referenceData: ClientReferenceDataPort;
  hasher: AgentIdentifierHasher;
  sealer: AgentSecretSealer;
  settings: AgentSettingsPort;
  content: AgentContentPort;
  uow: AgentUnitOfWork;
  audit: AgentAuditPort;
  clock: AgentClock;
  /** Injectable so tests are deterministic. */
  newId?: () => string;
  logger?: Pick<Logger, 'warn'>;
}

type CreateOutcome =
  | { ok: true; row: AgentClientDraftRecord }
  | Exclude<ClientDraftDecision, { ok: true }>;

export class AgentClientDraftService {
  private readonly newId: () => string;

  constructor(private readonly deps: AgentClientDraftServiceDeps) {
    this.newId = deps.newId ?? randomUUID;
  }

  /** POST /agent/clients: a new DRAFT. Nothing is sent to the client yet. */
  async create(
    claims: AgentAccessClaims,
    input: AgentClientDraftInput,
  ): Promise<ClientDraftView> {
    await assertAgentClientsEnabled(this.deps.settings);
    // The status is judged before the body: a paused agent gets 403, not 400.
    await this.deps.access.assertCan(claims, 'addMembers');
    const now = this.deps.clock.now();
    const phone = typeof input?.phone === 'string' ? input.phone : '';
    const checked = validateClientProfile(input?.details, now);
    const invalid = [
      ...(E164.test(phone) ? [] : ['phone']),
      ...(input?.consentConfirmed === true ? [] : ['consentConfirmed']),
      ...(checked.ok ? [] : checked.fields),
    ];
    if (invalid.length > 0 || !checked.ok) {
      throw new AgentServiceError('VALIDATION_FAILED', { fields: invalid });
    }
    const details = await this.withLabels(checked.profile);
    const { limit, expiryDays } = await this.draftSettings();
    // Before anything is looked up about the phone: every number that is not
    // an approved test number gets the same answer.
    if (!this.deps.proof.canReach(phone)) {
      throw new AgentServiceError('OTP_DELIVERY_UNAVAILABLE');
    }
    const hashes = this.deps.hasher.hashAll('PHONE', phone);

    let outcome: CreateOutcome;
    try {
      outcome = await this.deps.uow.run(async (tx): Promise<CreateOutcome> => {
        const { drafts, audit, sealer } = this.deps;
        await drafts.lockAgent(claims.sub, tx);
        // Re-checked under the lock: the status may have just changed.
        const agent = await this.deps.access.assertCan(claims, 'addMembers', {
          tx,
        });
        await this.closeOverdue(agent.id, now, tx);
        const decision = decideClientDraftCreate({
          ...(await this.phoneFacts(agent, phone, hashes, tx)),
          hasOpenDraftForPhone:
            (await drafts.findOpenByAgentAndHashes(agent.id, hashes, tx)) !==
            null,
          openCount: await drafts.countOpen(agent.id, tx),
          draftLimit: limit,
        });
        if (!decision.ok) {
          await this.auditRefusal(agent.id, decision, 'CREATE', tx);
          return decision;
        }
        const row = await drafts.create(
          {
            id: this.newId(),
            agentId: agent.id,
            phoneHash: hashes[0],
            phoneSealed: sealer.seal(AGENT_SEAL_PURPOSES.clientPhone, phone),
            phoneMasked: maskPhone(phone),
            displayName: displayNameOf(details, maskPhone(phone)),
            detailsSealed: sealer.seal(
              AGENT_SEAL_PURPOSES.clientDetails,
              JSON.stringify(details),
            ),
            expiresAt: clientDraftExpiresAt(now, expiryDays),
            createdAt: now,
          },
          tx,
        );
        await audit.record(
          {
            actorId: agent.id,
            action: 'AGENT_CLIENT_DRAFT_CREATED',
            entity: CLIENT_DRAFT_ENTITY,
            entityId: row.id,
            // The agent confirmed the client or family agreed. Only that.
            metadata: { consentConfirmed: true },
          },
          tx,
        );
        return { ok: true, row };
      });
    } catch (error) {
      // Two creates for the same phone at once: the database kept the first.
      if (
        error instanceof AgentConflictError &&
        error.reason === 'DUPLICATE_OPEN_CLIENT_DRAFT'
      ) {
        throw new AgentServiceError('CLIENT_DRAFT_EXISTS');
      }
      throw error;
    }
    if (!outcome.ok) throw refusal(outcome);
    return this.view(outcome.row, now);
  }

  /** GET /agent/clients: every draft of the agent, newest first. */
  async list(
    claims: AgentAccessClaims,
    query: AgentClientsQuery = {},
  ): Promise<AgentClientsPage> {
    await assertAgentClientsEnabled(this.deps.settings);
    const agent = await this.deps.access.assertCan(claims, 'viewReferrals');
    const { limit, status, after } = parseQuery(query);
    const now = this.deps.clock.now();
    const rows = await this.deps.drafts.listPageByAgent(
      agent.id,
      { status, now },
      { limit: limit + 1, after },
    );
    const page = rows.slice(0, limit);
    const labels = await this.labels();
    return {
      items: page.map((row) => this.viewWith(row, now, labels)),
      nextCursor:
        rows.length > limit ? encodeCursor(page[page.length - 1]) : null,
    };
  }

  /** GET /agent/clients/{id}. Another agent's draft looks like a missing one. */
  async get(claims: AgentAccessClaims, id: string): Promise<ClientDraftView> {
    await assertAgentClientsEnabled(this.deps.settings);
    const agent = await this.deps.access.assertCan(claims, 'viewReferrals');
    const row = await this.deps.drafts.findByIdForAgent(id, agent.id);
    if (row === null) throw new AgentServiceError('CLIENT_DRAFT_NOT_FOUND');
    return this.view(row, this.deps.clock.now());
  }

  /** PATCH /agent/clients/{id}: replaces the details of a DRAFT. */
  async update(
    claims: AgentAccessClaims,
    id: string,
    input: { details?: unknown },
  ): Promise<ClientDraftView> {
    await assertAgentClientsEnabled(this.deps.settings);
    await this.deps.access.assertCan(claims, 'addMembers');
    const now = this.deps.clock.now();
    const checked = validateClientProfile(input?.details, now);
    if (!checked.ok) {
      throw new AgentServiceError('VALIDATION_FAILED', {
        fields: checked.fields,
      });
    }
    const details = await this.withLabels(checked.profile);
    const row = await this.deps.uow.run(async (tx) => {
      const agent = await this.deps.access.assertCan(claims, 'addMembers', {
        tx,
      });
      const draft = await this.requireOwnDraft(id, agent.id, now, tx);
      const updated = await this.deps.drafts.updateDetails(
        id,
        agent.id,
        {
          displayName: displayNameOf(details, draft.phoneMasked),
          detailsSealed: this.deps.sealer.seal(
            AGENT_SEAL_PURPOSES.clientDetails,
            JSON.stringify(details),
          ),
        },
        now,
        tx,
      );
      if (updated === null) throw new AgentServiceError('CLIENT_DRAFT_LOCKED');
      await this.deps.audit.record(
        {
          actorId: agent.id,
          action: 'AGENT_CLIENT_DRAFT_UPDATED',
          entity: CLIENT_DRAFT_ENTITY,
          entityId: id,
          metadata: { fields: ['details'] },
        },
        tx,
      );
      return updated;
    });
    return this.view(row, now);
  }

  /** DELETE /agent/clients/{id}: a DRAFT and its details are deleted. */
  async discard(claims: AgentAccessClaims, id: string): Promise<void> {
    await assertAgentClientsEnabled(this.deps.settings);
    await this.deps.access.assertCan(claims, 'addMembers');
    const now = this.deps.clock.now();
    await this.deps.uow.run(async (tx) => {
      const agent = await this.deps.access.assertCan(claims, 'addMembers', {
        tx,
      });
      await this.requireOwnDraft(id, agent.id, now, tx);
      if (!(await this.deps.drafts.discard(id, agent.id, tx))) {
        throw new AgentServiceError('CLIENT_DRAFT_LOCKED');
      }
      await this.deps.audit.record(
        {
          actorId: agent.id,
          action: 'AGENT_CLIENT_DRAFT_DISCARDED',
          entity: CLIENT_DRAFT_ENTITY,
          entityId: id,
        },
        tx,
      );
    });
  }

  /**
   * POST /agent/clients/{id}/submit: DRAFT -> WAITING_FOR_CLIENT, locked for
   * good, open for `agent.client_draft_expiry_days` from now. The phone is
   * checked again. After the change has committed, a code is sent to the
   * client; if that fails (for example the code service is busy for that
   * phone) the submit still stands and the client asks for a code in the app.
   */
  async submit(
    claims: AgentAccessClaims,
    id: string,
  ): Promise<ClientDraftView> {
    await assertAgentClientsEnabled(this.deps.settings);
    await this.deps.access.assertCan(claims, 'addMembers');
    const { expiryDays } = await this.draftSettings();
    const now = this.deps.clock.now();
    const outcome = await this.deps.uow.run(
      async (
        tx,
      ): Promise<
        | { ok: true; row: AgentClientDraftRecord; phone: string }
        | Exclude<ClientDraftDecision, { ok: true }>
      > => {
        const agent = await this.deps.access.assertCan(claims, 'addMembers', {
          tx,
        });
        const draft = await this.requireOwnDraft(id, agent.id, now, tx);
        // Every required field (one list: client-profile-required.ts).
        const missing = missingRequiredClientFields(this.profileOf(draft));
        if (missing.length > 0) {
          throw new AgentServiceError('CLIENT_PROFILE_INCOMPLETE', {
            missingFields: missing,
          });
        }
        const phone = this.deps.sealer.open(
          AGENT_SEAL_PURPOSES.clientPhone,
          draft.phoneSealed ?? '',
        );
        const hashes = this.deps.hasher.hashAll('PHONE', phone);
        const decision = decideClientDraftSubmit(
          await this.phoneFacts(agent, phone, hashes, tx),
        );
        if (!decision.ok) {
          await this.auditRefusal(agent.id, decision, 'SUBMIT', tx);
          return decision;
        }
        const row = await this.deps.drafts.submit(
          id,
          agent.id,
          {
            submittedAt: now,
            expiresAt: clientDraftExpiresAt(now, expiryDays),
          },
          now,
          tx,
        );
        if (row === null) throw new AgentServiceError('CLIENT_DRAFT_LOCKED');
        await this.deps.audit.record(
          {
            actorId: agent.id,
            action: 'AGENT_CLIENT_DRAFT_SUBMITTED',
            entity: CLIENT_DRAFT_ENTITY,
            entityId: id,
          },
          tx,
        );
        return { ok: true, row, phone };
      },
    );
    if (!outcome.ok) throw refusal(outcome);
    try {
      await this.deps.proof.send(outcome.phone);
    } catch (error) {
      // Never the phone: the draft id and the kind of failure only.
      this.deps.logger?.warn(
        `No consent code was sent for client draft ${id} (${(error as Error).name}); the client can ask for one.`,
      );
    }
    return this.view(outcome.row, now);
  }

  /** The agent's own draft that is still a DRAFT (not submitted, closed or overdue). */
  private async requireOwnDraft(
    id: string,
    agentId: string,
    now: Date,
    tx: AgentTx,
  ): Promise<AgentClientDraftRecord> {
    const row = await this.deps.drafts.findByIdForAgent(id, agentId, tx);
    if (row === null) throw new AgentServiceError('CLIENT_DRAFT_NOT_FOUND');
    if (effectiveClientDraftStatus(row, now) !== 'DRAFT') {
      throw new AgentServiceError('CLIENT_DRAFT_LOCKED');
    }
    return row;
  }

  /** Everything that makes a phone unavailable to this agent, under every hash. */
  private async phoneFacts(
    agent: AgentRecord,
    phone: string,
    hashes: readonly string[],
    tx: AgentTx,
  ): Promise<ClientPhoneFacts> {
    let credited = false;
    for (const hash of hashes) {
      if (await this.deps.attributions.isPhoneHashCredited(hash, tx)) {
        credited = true;
        break;
      }
    }
    return {
      canReach: this.deps.proof.canReach(phone),
      phoneIsMember:
        (await this.deps.accounts.findMemberByPhone(phone, tx)) !== null,
      phoneCredited: credited,
      isAgentsOwnPhone: hashes.includes(agent.phoneHash),
      rejectedBefore: await this.deps.drafts.wasRejectedBy(
        agent.id,
        hashes,
        tx,
      ),
    };
  }

  /** A refused phone is audited (the internal reason only); the other refusals are not. */
  private async auditRefusal(
    agentId: string,
    decision: Exclude<ClientDraftDecision, { ok: true }>,
    step: 'CREATE' | 'SUBMIT',
    tx: AgentTx,
  ): Promise<void> {
    if (decision.reason !== 'PHONE_UNAVAILABLE') return;
    await this.deps.audit.record(
      {
        actorId: agentId,
        action: 'AGENT_CLIENT_DRAFT_REFUSED',
        entity: CLIENT_DRAFT_ENTITY,
        entityId: null,
        metadata: { reason: decision.refusal, step },
      },
      tx,
    );
  }

  /** Closes the agent's drafts whose time has run out, with an audit row each. */
  private async closeOverdue(
    agentId: string,
    now: Date,
    tx: AgentTx,
  ): Promise<void> {
    for (;;) {
      const ids = await this.deps.drafts.expireDue(
        agentId,
        now,
        AGENT_CLIENT_EXPIRY_BATCH_SIZE,
        tx,
      );
      for (const id of ids) {
        await this.deps.audit.record(
          {
            actorId: null,
            action: 'AGENT_CLIENT_DRAFT_EXPIRED',
            entity: CLIENT_DRAFT_ENTITY,
            entityId: id,
            metadata: { reason: 'TIMED_OUT' },
          },
          tx,
        );
      }
      if (ids.length < AGENT_CLIENT_EXPIRY_BATCH_SIZE) return;
    }
  }

  private async draftSettings(): Promise<{
    limit: number;
    expiryDays: number;
  }> {
    const keys = [
      AGENT_CLIENT_DRAFT_LIMIT_KEY,
      AGENT_CLIENT_DRAFT_EXPIRY_DAYS_KEY,
    ];
    const { settings } = parseAgentProgramSettings(
      await this.deps.settings.getMany(keys),
    );
    const limit = settings.agentClientDraftLimit;
    const expiryDays = settings.agentClientDraftExpiryDays;
    if (limit === undefined || expiryDays === undefined) {
      throw new AgentConfigError(
        keys.filter((key, i) => [limit, expiryDays][i] === undefined),
      );
    }
    return { limit, expiryDays };
  }

  private async labels() {
    return (await this.deps.content.getContent()).clientStatusLabels;
  }

  private async view(
    row: AgentClientDraftRecord,
    now: Date,
  ): Promise<ClientDraftView> {
    return this.viewWith(row, now, await this.labels());
  }

  private viewWith(
    row: AgentClientDraftRecord,
    now: Date,
    labels: Awaited<ReturnType<AgentClientDraftService['labels']>>,
  ): ClientDraftView {
    const status = effectiveClientDraftStatus(row, now);
    const open = status === 'DRAFT' || status === 'WAITING_FOR_CLIENT';
    const details =
      open && row.detailsSealed !== null ? this.profileOf(row) : null;
    return clientDraftView(row, now, { labels, details });
  }

  /** The draft's opened profile (empty when it has none). */
  private profileOf(row: AgentClientDraftRecord): ClientProfile {
    return row.detailsSealed === null
      ? {}
      : parseStoredClientProfile(
          this.deps.sealer.open(
            AGENT_SEAL_PURPOSES.clientDetails,
            row.detailsSealed,
          ),
        );
  }

  /** The master-data labels filled in; a code the master data refuses is VALIDATION_FAILED. */
  private async withLabels(profile: ClientProfile): Promise<ClientProfile> {
    const resolved = await this.deps.referenceData.withLabels(profile);
    if (!resolved.ok) {
      throw new AgentServiceError('VALIDATION_FAILED', {
        fields: resolved.fields,
      });
    }
    return resolved.profile;
  }
}

/**
 * "Priya S.", or the masked phone while the names are not filled in yet (a
 * draft may be saved before them).
 */
function displayNameOf(profile: ClientProfile, phoneMasked: string): string {
  const first = profile.basicDetails?.firstName;
  const last = profile.basicDetails?.lastName;
  return typeof first === 'string' && first !== ''
    ? toDisplayName(first, typeof last === 'string' ? last : null)
    : phoneMasked;
}

/** The agent hears one code per refusal; the phone reasons stay internal. */
function refusal(
  decision: Exclude<ClientDraftDecision, { ok: true }>,
): AgentServiceError {
  switch (decision.reason) {
    case 'DELIVERY_UNAVAILABLE':
      return new AgentServiceError('OTP_DELIVERY_UNAVAILABLE');
    case 'DRAFT_EXISTS':
      return new AgentServiceError('CLIENT_DRAFT_EXISTS');
    case 'LIMIT_REACHED':
      return new AgentServiceError('CLIENT_DRAFT_LIMIT_REACHED');
    case 'PHONE_UNAVAILABLE':
      return new AgentServiceError('CLIENT_PHONE_UNAVAILABLE');
  }
}

function parseQuery(query: AgentClientsQuery): {
  limit: number;
  status: ClientDraftStatus | undefined;
  after: ClientDraftPageCursor | undefined;
} {
  const invalid: string[] = [];
  let limit = DEFAULT_CLIENTS_PAGE_LIMIT;
  if (query.limit !== undefined) {
    if (
      !Number.isSafeInteger(query.limit) ||
      query.limit < 1 ||
      query.limit > MAX_CLIENTS_PAGE_LIMIT
    ) {
      invalid.push('limit');
    } else {
      limit = query.limit;
    }
  }
  let status: ClientDraftStatus | undefined;
  if (query.status !== undefined) {
    if (CLIENT_DRAFT_STATUSES.includes(query.status as ClientDraftStatus)) {
      status = query.status as ClientDraftStatus;
    } else {
      invalid.push('status');
    }
  }
  let after: ClientDraftPageCursor | undefined;
  if (query.cursor !== undefined) {
    after = decodeCursor(query.cursor);
    if (after === undefined) invalid.push('cursor');
  }
  if (invalid.length > 0) {
    throw new AgentServiceError('VALIDATION_FAILED', { fields: invalid });
  }
  return { limit, status, after };
}

/** Opaque to clients: base64url of { t: ISO time, i: draft id }. */
function encodeCursor(row: AgentClientDraftRecord): string {
  return Buffer.from(
    JSON.stringify({ t: row.createdAt.toISOString(), i: row.id }),
  ).toString('base64url');
}

function decodeCursor(cursor: string): ClientDraftPageCursor | undefined {
  if (
    typeof cursor !== 'string' ||
    cursor.length === 0 ||
    cursor.length > 200
  ) {
    return undefined;
  }
  try {
    const parsed = JSON.parse(
      Buffer.from(cursor, 'base64url').toString('utf8'),
    ) as { t?: unknown; i?: unknown };
    if (typeof parsed.t !== 'string' || typeof parsed.i !== 'string') {
      return undefined;
    }
    const at = new Date(parsed.t);
    if (
      Number.isNaN(at.getTime()) ||
      at.toISOString() !== parsed.t ||
      parsed.i.length === 0 ||
      parsed.i.length > 100
    ) {
      return undefined;
    }
    return { at, id: parsed.i };
  } catch {
    return undefined;
  }
}
