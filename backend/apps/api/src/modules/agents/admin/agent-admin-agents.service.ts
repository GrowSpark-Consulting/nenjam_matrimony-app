/**
 * The first admin agent routes: summary, list, detail, approve, reject
 * (docs/agent-program/agent-admin-api.openapi.yaml).
 *
 * Every method runs in one `AgentUnitOfWork` transaction. The permission is
 * checked FIRST, inside that transaction (the guard already checked it on
 * the way in; this re-checks against the same rows the change depends on),
 * then the state, then the change, and the audit row is written in the same
 * transaction, so a failed audit write rolls the change back. State moves go
 * through `canTransitionAgentStatus`. Output is masked: no sealed value, no
 * full phone, no full PAN, no full payout details.
 */
import { randomUUID } from 'node:crypto';
import {
  canTransitionAgentStatus,
  type AgentStatus,
} from '../agent/agent-status';
import { AgentMoneyError } from '../errors/agent-money-error';
import type {
  AdminAgentListFilter,
  AdminAgentRow,
  AgentAdminReadPort,
} from '../ports/agent-admin-read.port';
import {
  AgentConflictError,
  type AgentPayoutDetailsRepository,
  type AgentRecord,
  type AgentRepository,
  type ReferralAttributionRepository,
  type ReferralCodeRepository,
} from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type {
  AgentAuditPort,
  AgentIdentifierHasher,
  AgentPermissionPort,
} from '../ports/agent-platform-ports';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';
import { maskPhone } from '../referral/agent-referral-view';
import { normalizeReferralCode } from '../referral/normalize-referral-code';
import {
  generateUniqueReferralCode,
  type RandomInt,
} from '../referral/referral-code';

/** The staff member behind the request (filled by the controller). */
export interface AdminActor {
  userId: string;
  context?: { requestId: string; ipAddress?: string; userAgent?: string };
}

export interface AgentAdminAgentsServiceDeps {
  uow: AgentUnitOfWork;
  agents: AgentRepository;
  codes: ReferralCodeRepository;
  payoutDetails: AgentPayoutDetailsRepository;
  attributions: ReferralAttributionRepository;
  read: AgentAdminReadPort;
  permission: AgentPermissionPort;
  audit: AgentAuditPort;
  hasher: AgentIdentifierHasher;
  clock: AgentClock;
}

export interface AgentsSummaryView {
  byStatus: Record<AgentStatus, number>;
  payoutDetailsAwaitingVerification: number;
  referralsNeedingReview: number;
  /** Null until the commission tables exist. */
  commissionsReady: number | null;
  /** Null until the payout tables exist. */
  payoutsCreated: number | null;
}

export interface AdminAgentListItemView {
  id: string;
  name: string;
  phoneMasked: string;
  city: string;
  state: string;
  status: AgentStatus;
  createdAt: string;
  approvedAt: string | null;
  panOnFile: boolean;
  panVerified: boolean;
  payoutDetailsSet: boolean;
  payoutDetailsVerified: boolean;
  primaryCode: string | null;
}

export interface AdminAgentDetailView {
  id: string;
  name: string;
  phoneMasked: string;
  city: string;
  state: string;
  status: AgentStatus;
  rejectionReason: string | null;
  approvedAt: string | null;
  createdAt: string;
  updatedAt: string;
  panLast4: string | null;
  panOnFile: boolean;
  panVerifiedAt: string | null;
  payoutDetailsSet: boolean;
  payoutDetails: {
    method: 'UPI' | 'BANK';
    display: string;
    verifiedAt: string | null;
    changedAt: string;
  } | null;
  codes: Array<{
    id: string;
    code: string;
    isPrimary: boolean;
    isActive: boolean;
    createdAt: string;
  }>;
  counts: {
    referrals: number;
    byAttributionStatus: Record<string, number>;
    needsReview: number;
  };
  /** Null until the commission tables exist. */
  commissions: null;
  statusHistory: Array<{
    from: AgentStatus;
    to: AgentStatus;
    at: string;
    actorId: string | null;
    actorType: 'STAFF' | 'MEMBER' | 'AGENT' | 'SYSTEM';
    reason: string | null;
  }>;
}

export interface AgentListQuery {
  status?: AgentStatus;
  /** An agent id, a referral code (NM...), a full E.164 phone, or a name prefix. */
  q?: string;
  /** Case-insensitive prefix of the agent's name. */
  name?: string;
  cursor?: string;
  /** 1 to 100, default 25. */
  limit?: number;
}

export const PERMISSION_AGENT_VIEW = { module: 'agent', action: 'view' };
export const PERMISSION_AGENT_APPROVE = { module: 'agent', action: 'approve' };

const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;
/** Codes generated before giving up on a collision (not a business value). */
const CODE_ATTEMPTS = 10;
/** Whole-transaction retries when a code collides at insert (a race). */
const APPROVE_ATTEMPTS = 3;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const E164 = /^\+[1-9][0-9]{7,14}$/;

export class AgentAdminAgentsService {
  private readonly newId: () => string;
  private readonly random?: RandomInt;

  constructor(
    private readonly deps: AgentAdminAgentsServiceDeps,
    options: { newId?: () => string; random?: RandomInt } = {},
  ) {
    this.newId = options.newId ?? randomUUID;
    this.random = options.random;
  }

  summary(actor: AdminActor): Promise<AgentsSummaryView> {
    return this.deps.uow.run(async (tx) => {
      await this.deps.permission.assert(
        actor.userId,
        PERMISSION_AGENT_VIEW,
        tx,
      );
      const counts = await this.deps.read.summary(tx);
      return { ...counts, commissionsReady: null, payoutsCreated: null };
    });
  }

  list(
    actor: AdminActor,
    query: AgentListQuery = {},
  ): Promise<{ items: AdminAgentListItemView[]; nextCursor: string | null }> {
    const limit = query.limit ?? DEFAULT_LIMIT;
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > MAX_LIMIT) {
      throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['limit'] });
    }
    const after = decodeCursor(query.cursor);
    return this.deps.uow.run(async (tx) => {
      await this.deps.permission.assert(
        actor.userId,
        PERMISSION_AGENT_VIEW,
        tx,
      );
      const filter = await this.filterFor(query, tx);
      if (filter === null) return { items: [], nextCursor: null };
      const rows = await this.deps.read.listAgents(
        filter,
        { limit: limit + 1, after },
        tx,
      );
      const page = rows.slice(0, limit);
      const last = page[page.length - 1];
      return {
        items: page.map(toListItem),
        nextCursor:
          rows.length > limit && last
            ? encodeCursor({ at: last.agent.createdAt, id: last.agent.id })
            : null,
      };
    });
  }

  get(actor: AdminActor, id: string): Promise<AdminAgentDetailView> {
    return this.deps.uow.run(async (tx) => {
      await this.deps.permission.assert(
        actor.userId,
        PERMISSION_AGENT_VIEW,
        tx,
      );
      return this.detail(id, tx);
    });
  }

  /**
   * PENDING_APPROVAL -> ACTIVE: sets approvedAt, clears rejectionReason,
   * issues the agent's first primary code (only if it has none), audits.
   * The reason is internal (audit only). A code that collides at insert (a
   * race the uniqueness check cannot see) retries the whole transaction.
   */
  async approve(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminAgentDetailView> {
    const text = requireReason(reason);
    for (let attempt = 1; ; attempt++) {
      try {
        return await this.deps.uow.run((tx) =>
          this.move(
            actor,
            id,
            text,
            'ACTIVE',
            'agent.approve',
            tx,
            async (agent, now) => {
              const codes = await this.deps.codes.listByAgent(agent.id, tx);
              if (codes.length === 0) {
                const code = await generateUniqueReferralCode(
                  (candidate) => this.deps.codes.codeExists(candidate, tx),
                  CODE_ATTEMPTS,
                  this.random,
                );
                await this.deps.codes.create(
                  {
                    id: this.newId(),
                    agentId: agent.id,
                    code,
                    isPrimary: true,
                    isActive: true,
                    createdAt: now,
                  },
                  tx,
                );
              }
              return { approvedAt: now, rejectionReason: null };
            },
          ),
        );
      } catch (error) {
        if (
          attempt < APPROVE_ATTEMPTS &&
          error instanceof AgentConflictError &&
          error.reason === 'DUPLICATE_CODE'
        ) {
          continue;
        }
        throw error;
      }
    }
  }

  /** PENDING_APPROVAL -> REJECTED. The one reason is shown to the applicant. */
  async reject(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminAgentDetailView> {
    const text = requireReason(reason);
    return await this.deps.uow.run((tx) =>
      this.move(actor, id, text, 'REJECTED', 'agent.reject', tx, () =>
        Promise.resolve({ rejectionReason: text }),
      ),
    );
  }

  // --- internals --------------------------------------------------------------

  private async move(
    actor: AdminActor,
    id: string,
    reason: string,
    to: AgentStatus,
    action: string,
    tx: AgentTx,
    apply: (
      agent: AgentRecord,
      now: Date,
    ) => Promise<Partial<Pick<AgentRecord, 'approvedAt' | 'rejectionReason'>>>,
  ): Promise<AdminAgentDetailView> {
    await this.deps.permission.assert(
      actor.userId,
      PERMISSION_AGENT_APPROVE,
      tx,
    );
    const agent = await this.deps.agents.findById(id, tx);
    if (agent === null) throw new AgentMoneyError('AGENT_NOT_FOUND');
    // Approve and reject are for applications only: the state machine also
    // allows SUSPENDED -> ACTIVE, but that is "resume", not "approve".
    const decision =
      agent.status === 'PENDING_APPROVAL'
        ? canTransitionAgentStatus(agent.status, to)
        : agent.status === to
          ? ({ allowed: false, reason: 'SAME_STATUS' } as const)
          : agent.status === 'TERMINATED'
            ? ({ allowed: false, reason: 'TERMINATED_IS_FINAL' } as const)
            : ({ allowed: false, reason: 'TRANSITION_NOT_ALLOWED' } as const);
    if (!decision.allowed) {
      throw new AgentMoneyError('AGENT_TRANSITION_NOT_ALLOWED', {
        agentStatus: agent.status,
        refusal: decision.reason,
      });
    }
    const now = this.deps.clock.now();
    const extra = await apply(agent, now);
    await this.deps.agents.update(id, { status: to, ...extra }, tx);
    await this.deps.audit.record(
      {
        actorId: actor.userId,
        actorType: 'STAFF',
        action,
        entity: 'Agent',
        entityId: id,
        reason,
        before: { status: agent.status },
        after: { status: to },
        context: actor.context,
      },
      tx,
    );
    return this.detail(id, tx);
  }

  private async detail(id: string, tx: AgentTx): Promise<AdminAgentDetailView> {
    const row = await this.deps.read.findAgentRow(id, tx);
    if (row === null) throw new AgentMoneyError('AGENT_NOT_FOUND');
    const { agent } = row;
    const [details, codes, attributions, history] = await Promise.all([
      this.deps.payoutDetails.find(id, tx),
      this.deps.codes.listByAgent(id, tx),
      this.deps.attributions.listByAgent(id, tx),
      this.deps.read.statusHistory(id, tx),
    ]);
    const byAttributionStatus: Record<string, number> = {
      ACTIVE: 0,
      CONVERTED: 0,
      EXPIRED: 0,
      REJECTED: 0,
    };
    for (const a of attributions) {
      byAttributionStatus[a.status] = (byAttributionStatus[a.status] ?? 0) + 1;
    }
    return {
      id: agent.id,
      name: agent.name,
      phoneMasked: maskPhone(agent.phoneE164),
      city: agent.city,
      state: agent.state,
      status: agent.status,
      rejectionReason: agent.rejectionReason,
      approvedAt: iso(agent.approvedAt),
      createdAt: agent.createdAt.toISOString(),
      updatedAt: row.updatedAt.toISOString(),
      panLast4: agent.panLast4,
      panOnFile: agent.panSealed !== null,
      panVerifiedAt: iso(agent.panVerifiedAt),
      payoutDetailsSet: agent.payoutDetailsSet,
      payoutDetails: details
        ? {
            method: details.method,
            display: details.display,
            verifiedAt: iso(details.verifiedAt),
            changedAt: details.changedAt.toISOString(),
          }
        : null,
      codes: codes.map((c) => ({
        id: c.id,
        code: c.code,
        isPrimary: c.isPrimary,
        isActive: c.isActive,
        createdAt: c.createdAt.toISOString(),
      })),
      counts: {
        referrals: attributions.length,
        byAttributionStatus,
        needsReview: attributions.filter((a) => a.needsReview).length,
      },
      commissions: null,
      statusHistory: history.map((h) => ({
        from: h.from,
        to: h.to,
        at: h.at.toISOString(),
        actorId: h.actorId,
        actorType: h.actorType,
        reason: h.reason,
      })),
    };
  }

  /**
   * `q`: an exact agent id (UUID), a referral code, a full E.164 phone
   * (hashed under every active pepper version), or else a name prefix.
   * `name`: a name prefix. Both given: both must match. Null means "nothing
   * can match" (an unknown code).
   */
  private async filterFor(
    query: AgentListQuery,
    tx: AgentTx,
  ): Promise<AdminAgentListFilter | null> {
    const filter: AdminAgentListFilter = {};
    if (query.status !== undefined) filter.status = query.status;
    const name = query.name?.trim();
    if (name !== undefined && name !== '') {
      if (name.length < 2) {
        throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['name'] });
      }
      filter.namePrefix = name;
    }
    const q = query.q?.trim();
    if (!q) return filter;
    if (UUID.test(q)) {
      filter.ids = [q.toLowerCase()];
      return filter;
    }
    if (E164.test(q)) {
      filter.phoneHashes = this.deps.hasher.hashAll('PHONE', q);
      return filter;
    }
    const code = normalizeReferralCode(q);
    if (code !== null) {
      const found = await this.deps.codes.findByCode(code, tx);
      if (found === null) return null;
      filter.ids = [found.agentId];
      return filter;
    }
    if (q.length < 2) {
      throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['q'] });
    }
    if (filter.namePrefix !== undefined && filter.namePrefix !== q) {
      // Two different name prefixes: the shorter one adds nothing.
      filter.namePrefix =
        q.length > filter.namePrefix.length ? q : filter.namePrefix;
    } else {
      filter.namePrefix = q;
    }
    return filter;
  }
}

function toListItem(row: AdminAgentRow): AdminAgentListItemView {
  const { agent } = row;
  return {
    id: agent.id,
    name: agent.name,
    phoneMasked: maskPhone(agent.phoneE164),
    city: agent.city,
    state: agent.state,
    status: agent.status,
    createdAt: agent.createdAt.toISOString(),
    approvedAt: iso(agent.approvedAt),
    panOnFile: agent.panSealed !== null,
    panVerified: agent.panVerifiedAt !== null,
    payoutDetailsSet: agent.payoutDetailsSet,
    payoutDetailsVerified: row.payoutDetailsVerified,
    primaryCode: row.primaryCode,
  };
}

const iso = (value: Date | null): string | null =>
  value === null ? null : value.toISOString();

/** A reason is 3 to 500 characters once trimmed. Returns the trimmed text. */
export function requireReason(value: unknown): string {
  const text = typeof value === 'string' ? value.trim() : '';
  if (text.length < 3 || text.length > 500) {
    throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['reason'] });
  }
  return text;
}

export function encodeCursor(position: { at: Date; id: string }): string {
  return Buffer.from(`${position.at.toISOString()}|${position.id}`).toString(
    'base64url',
  );
}

export function decodeCursor(
  cursor: string | undefined,
): { at: Date; id: string } | undefined {
  if (cursor === undefined || cursor === '') return undefined;
  const text = Buffer.from(cursor, 'base64url').toString('utf8');
  const bar = text.indexOf('|');
  const at = new Date(bar < 0 ? NaN : text.slice(0, bar));
  const id = bar < 0 ? '' : text.slice(bar + 1);
  if (Number.isNaN(at.getTime()) || id === '') {
    throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['cursor'] });
  }
  return { at, id };
}
