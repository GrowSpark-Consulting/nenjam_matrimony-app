/**
 * Admin operations on agents: list, detail, approve, reject, pause, resume,
 * terminate, replace code, verify payout details, verify PAN, reveal.
 *
 * Every method runs in one `AgentUnitOfWork` transaction: the permission is
 * checked first, then the state, then the change, and the audit row is
 * written in the same transaction (if the audit write fails the change rolls
 * back). State moves go through `canTransitionAgentStatus`. Nothing sealed
 * leaves except through `reveal`, which needs `agent.pii.reveal` AND a fresh
 * step-up and audits one row per revealed field (never the value).
 */
import { randomUUID } from 'node:crypto';
import { canTransitionAgentStatus } from '../agent/agent-status';
import { AgentMoneyError } from '../errors/agent-money-error';
import type {
  AgentPayoutDetailsRepository,
  AgentRecord,
  AgentRepository,
  ReferralAttributionRepository,
  ReferralCodeRepository,
} from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type { AgentStatusHistoryPort } from '../ports/agent-money-ports';
import type {
  AgentAuditPort,
  AgentIdentifierHasher,
  AgentPermissionPort,
} from '../ports/agent-platform-ports';
import type { AgentSecretSealer } from '../ports/agent-secret-sealer.port';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';
import {
  generateUniqueReferralCode,
  type RandomInt,
} from '../referral/referral-code';
import {
  PAYOUT_RELATED_STATUSES,
  PERM,
  decodeCursor,
  encodeCursor,
  pageLimit,
  requireId,
  requirePermission,
  requireReason,
  toAgentListItem,
  toReferralCode,
  type AdminActor,
  type AdminAgentListItem,
  type AdminReferralCode,
  type PermissionKey,
} from './agent-admin-support';

export interface AgentAdminServiceDeps {
  uow: AgentUnitOfWork;
  agents: AgentRepository;
  codes: ReferralCodeRepository;
  payoutDetails: AgentPayoutDetailsRepository;
  attributions: ReferralAttributionRepository;
  permission: AgentPermissionPort;
  audit: AgentAuditPort;
  clock: AgentClock;
  sealer: AgentSecretSealer;
  hasher: AgentIdentifierHasher;
  history: AgentStatusHistoryPort;
}

export interface AdminAgentDetail extends AdminAgentListItem {
  rejectionReason: string | null;
  approvedAt: string | null;
  panVerifiedAt: string | null;
  payoutDetails: {
    method: string;
    display: string;
    verifiedAt: string | null;
    changedAt: string;
  } | null;
  codes: AdminReferralCode[];
  referralCount: number;
  statusHistory: Array<{
    action: string;
    at: string;
    actorId: string | null;
    reason: string | null;
  }>;
}

export type RevealField = 'PAN' | 'PAYOUT_DETAILS' | 'PHONE';

export interface RevealedValues {
  revealedAt: string;
  pan?: string;
  phone?: string;
  payoutDetails?: Record<string, unknown>;
}

export interface AgentListQuery {
  status?: AgentRecord['status'];
  /** An agent id, a referral code (NM...) or a full E.164 phone. */
  q?: string;
  /** At least two characters. */
  name?: string;
  cursor?: string;
  limit?: number;
}

const CODE_ATTEMPTS = 10;

export class AgentAdminService {
  private readonly newId: () => string;
  private readonly random?: RandomInt;

  constructor(
    private readonly deps: AgentAdminServiceDeps,
    options: { newId?: () => string; random?: RandomInt } = {},
  ) {
    this.newId = options.newId ?? randomUUID;
    this.random = options.random;
  }

  // --- reads ----------------------------------------------------------------

  async list(
    actor: AdminActor,
    query: AgentListQuery = {},
  ): Promise<{ items: AdminAgentListItem[]; nextCursor: string | null }> {
    const limit = pageLimit(query.limit);
    const after = decodeCursor(query.cursor);
    if (query.name !== undefined && query.name.trim().length < 2) {
      throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['name'] });
    }
    return this.deps.uow.run(async (tx) => {
      await requirePermission(this.deps.permission, actor, PERM.agentView, tx);
      const filter = await this.filterFor(query, tx);
      if (filter === 'NONE') return { items: [], nextCursor: null };
      const rows = await this.deps.agents.listPage(
        filter,
        { limit: limit + 1, after },
        tx,
      );
      const page = rows.slice(0, limit);
      const last = page[page.length - 1];
      return {
        items: page.map(toAgentListItem),
        nextCursor:
          rows.length > limit && last
            ? encodeCursor({ at: last.createdAt, id: last.id })
            : null,
      };
    });
  }

  async get(actor: AdminActor, id: string): Promise<AdminAgentDetail> {
    requireId('id', id);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(this.deps.permission, actor, PERM.agentView, tx);
      return this.detail(await this.mustFind(id, tx), tx);
    });
  }

  // --- state moves ----------------------------------------------------------

  /** PENDING_APPROVAL -> ACTIVE; creates the first primary code. */
  approve(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminAgentDetail> {
    return this.move(actor, id, reason, {
      to: 'ACTIVE',
      permission: PERM.agentApprove,
      action: 'agent.approve',
      apply: async (agent, tx, now) => {
        const hasCode =
          (await this.deps.codes.listByAgent(agent.id, tx)).length > 0;
        if (!hasCode) await this.issueCode(agent.id, true, tx, now);
        return { approvedAt: now, rejectionReason: null };
      },
    });
  }

  /** PENDING_APPROVAL -> REJECTED. The reason is shown to the applicant. */
  reject(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminAgentDetail> {
    return this.move(actor, id, reason, {
      to: 'REJECTED',
      permission: PERM.agentApprove,
      action: 'agent.reject',
      apply: (_agent, _tx, _now, text) =>
        Promise.resolve({ rejectionReason: text }),
    });
  }

  pause(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminAgentDetail> {
    return this.move(actor, id, reason, {
      to: 'SUSPENDED',
      permission: PERM.agentManage,
      action: 'agent.pause',
    });
  }

  resume(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminAgentDetail> {
    return this.move(actor, id, reason, {
      to: 'ACTIVE',
      permission: PERM.agentManage,
      action: 'agent.resume',
    });
  }

  terminate(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminAgentDetail> {
    return this.move(actor, id, reason, {
      to: 'TERMINATED',
      permission: PERM.agentManage,
      action: 'agent.terminate',
    });
  }

  // --- codes ----------------------------------------------------------------

  /**
   * A new primary code; the old primary stays active (old codes keep working)
   * but is no longer primary. Demote before promoting: the database allows one
   * primary code per agent.
   */
  async replaceCode(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<{ primary: AdminReferralCode; codes: AdminReferralCode[] }> {
    requireId('id', id);
    const text = requireReason(reason);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.agentManage,
        tx,
      );
      const agent = await this.mustFind(id, tx);
      if (agent.status !== 'ACTIVE' && agent.status !== 'SUSPENDED') {
        throw new AgentMoneyError('AGENT_STATUS_NOT_ALLOWED', {
          agentStatus: agent.status,
        });
      }
      const before = await this.deps.codes.listByAgent(id, tx);
      const oldPrimary = before.find((c) => c.isPrimary);
      if (oldPrimary)
        await this.deps.codes.setPrimary(oldPrimary.id, false, tx);
      const created = await this.issueCode(id, true, tx, this.deps.clock.now());
      await this.deps.audit.record(
        {
          actorId: actor.userId,
          action: 'agent.code.replace',
          entity: 'Agent',
          entityId: id,
          reason: text,
          before: { primaryCodeId: oldPrimary?.id ?? null },
          after: { primaryCodeId: created.id },
        },
        tx,
      );
      return {
        primary: toReferralCode(created),
        codes: (await this.deps.codes.listByAgent(id, tx)).map(toReferralCode),
      };
    });
  }

  // --- verification -----------------------------------------------------------

  async verifyPayoutDetails(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminAgentDetail> {
    requireId('id', id);
    const text = requireReason(reason);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.agentPayoutDetailsVerify,
        tx,
      );
      const agent = await this.mustFind(id, tx);
      this.requirePayoutRelatedStatus(agent);
      const details = await this.deps.payoutDetails.find(id, tx);
      if (details === null) throw new AgentMoneyError('PAYOUT_DETAILS_NOT_SET');
      if (details.verifiedAt !== null) {
        throw new AgentMoneyError('PAYOUT_DETAILS_ALREADY_VERIFIED');
      }
      const now = this.deps.clock.now();
      await this.deps.payoutDetails.save({ ...details, verifiedAt: now }, tx);
      await this.deps.audit.record(
        {
          actorId: actor.userId,
          action: 'agent.payout_details.verify',
          entity: 'Agent',
          entityId: id,
          reason: text,
          before: {
            verified: false,
            changedAt: details.changedAt.toISOString(),
          },
          after: { verified: true },
        },
        tx,
      );
      return this.detail(agent, tx);
    });
  }

  async verifyPan(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminAgentDetail> {
    requireId('id', id);
    const text = requireReason(reason);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.agentPayoutDetailsVerify,
        tx,
      );
      const agent = await this.mustFind(id, tx);
      this.requirePayoutRelatedStatus(agent);
      if (agent.panSealed === null) throw new AgentMoneyError('PAN_NOT_SET');
      if (agent.panVerifiedAt !== null) {
        throw new AgentMoneyError('PAN_ALREADY_VERIFIED');
      }
      const updated = await this.deps.agents.update(
        id,
        { panVerifiedAt: this.deps.clock.now() },
        tx,
      );
      await this.deps.audit.record(
        {
          actorId: actor.userId,
          action: 'agent.pan.verify',
          entity: 'Agent',
          entityId: id,
          reason: text,
          before: { panVerified: false },
          after: { panVerified: true },
        },
        tx,
      );
      return this.detail(updated, tx);
    });
  }

  // --- reveal -------------------------------------------------------------------

  /**
   * The only door to a full PAN, a full phone number or the full payout
   * details. One audit row per revealed field (the field name, never the
   * value), in the same transaction as the read: if an audit write fails,
   * nothing is returned. A field that is not on file fails the whole request
   * and nothing is revealed or audited.
   */
  async reveal(
    actor: AdminActor,
    id: string,
    fields: readonly RevealField[],
    reason: string,
  ): Promise<RevealedValues> {
    requireId('id', id);
    const text = requireReason(reason);
    const wanted = [...new Set(fields)];
    if (wanted.length === 0 || wanted.length !== fields.length) {
      throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['fields'] });
    }
    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.agentPiiReveal,
        tx,
      );
      const agent = await this.mustFind(id, tx);
      const revealedAt = this.deps.clock.now();
      const result: RevealedValues = { revealedAt: revealedAt.toISOString() };

      // Check everything is on file before opening or auditing anything.
      const details = wanted.includes('PAYOUT_DETAILS')
        ? await this.deps.payoutDetails.find(id, tx)
        : null;
      if (wanted.includes('PAN') && agent.panSealed === null) {
        throw new AgentMoneyError('PAN_NOT_SET');
      }
      if (wanted.includes('PAYOUT_DETAILS') && details === null) {
        throw new AgentMoneyError('PAYOUT_DETAILS_NOT_SET');
      }

      for (const field of wanted) {
        if (field === 'PAN')
          result.pan = this.deps.sealer.open(agent.panSealed as string);
        if (field === 'PHONE') result.phone = agent.phoneE164;
        if (field === 'PAYOUT_DETAILS') {
          result.payoutDetails = JSON.parse(
            this.deps.sealer.open(
              (details as { detailsSealed: string }).detailsSealed,
            ),
          ) as Record<string, unknown>;
        }
        await this.deps.audit.record(
          {
            actorId: actor.userId,
            action: 'agent.pii.reveal',
            entity: 'Agent',
            entityId: id,
            reason: text,
            metadata: { field },
          },
          tx,
        );
      }
      return result;
    });
  }

  // --- internals ----------------------------------------------------------------

  private async move(
    actor: AdminActor,
    id: string,
    reason: string,
    step: {
      to: AgentRecord['status'];
      permission: PermissionKey;
      action: string;
      apply?: (
        agent: AgentRecord,
        tx: AgentTx,
        now: Date,
        reason: string,
      ) => Promise<
        Partial<Pick<AgentRecord, 'approvedAt' | 'rejectionReason'>>
      >;
    },
  ): Promise<AdminAgentDetail> {
    requireId('id', id);
    const text = requireReason(reason);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(this.deps.permission, actor, step.permission, tx);
      const agent = await this.mustFind(id, tx);
      const decision = canTransitionAgentStatus(agent.status, step.to);
      if (!decision.allowed) {
        throw new AgentMoneyError('AGENT_TRANSITION_NOT_ALLOWED', {
          agentStatus: agent.status,
          refusal: decision.reason,
        });
      }
      const now = this.deps.clock.now();
      const extra = step.apply ? await step.apply(agent, tx, now, text) : {};
      const updated = await this.deps.agents.update(
        id,
        { status: step.to, ...extra },
        tx,
      );
      await this.deps.audit.record(
        {
          actorId: actor.userId,
          action: step.action,
          entity: 'Agent',
          entityId: id,
          reason: text,
          before: { status: agent.status },
          after: { status: step.to },
        },
        tx,
      );
      return this.detail(updated, tx);
    });
  }

  private async mustFind(id: string, tx: AgentTx): Promise<AgentRecord> {
    const agent = await this.deps.agents.findById(id, tx);
    if (agent === null) throw new AgentMoneyError('AGENT_NOT_FOUND');
    return agent;
  }

  private requirePayoutRelatedStatus(agent: AgentRecord): void {
    if (!PAYOUT_RELATED_STATUSES.has(agent.status)) {
      throw new AgentMoneyError('AGENT_STATUS_NOT_ALLOWED', {
        agentStatus: agent.status,
      });
    }
  }

  private async issueCode(
    agentId: string,
    primary: boolean,
    tx: AgentTx,
    now: Date,
  ) {
    const code = await generateUniqueReferralCode(
      (candidate) => this.deps.codes.codeExists(candidate, tx),
      CODE_ATTEMPTS,
      this.random,
    );
    return this.deps.codes.create(
      {
        id: this.newId(),
        agentId,
        code,
        isPrimary: primary,
        isActive: true,
        createdAt: now,
      },
      tx,
    );
  }

  private async filterFor(query: AgentListQuery, tx: AgentTx) {
    const filter: Parameters<AgentRepository['listPage']>[0] = {};
    if (query.status !== undefined) filter.status = query.status;
    if (query.name !== undefined) filter.namePrefix = query.name.trim();
    const q = query.q?.trim();
    if (q) {
      if (q.startsWith('+')) {
        filter.phoneHash = this.deps.hasher.hash('PHONE', q);
      } else if (/^NM[0-9A-Z]{6}$/i.test(q)) {
        const code = await this.deps.codes.findByCode(q.toUpperCase(), tx);
        if (code === null) return 'NONE' as const;
        filter.ids = [code.agentId];
      } else {
        filter.ids = [q];
      }
    }
    return filter;
  }

  private async detail(
    agent: AgentRecord,
    tx: AgentTx,
  ): Promise<AdminAgentDetail> {
    const [details, codes, referrals, history] = await Promise.all([
      this.deps.payoutDetails.find(agent.id, tx),
      this.deps.codes.listByAgent(agent.id, tx),
      this.deps.attributions.listByAgent(agent.id, tx),
      this.deps.history.listForAgent(agent.id, tx),
    ]);
    return {
      ...toAgentListItem(agent),
      rejectionReason: agent.rejectionReason,
      approvedAt: agent.approvedAt?.toISOString() ?? null,
      panVerifiedAt: agent.panVerifiedAt?.toISOString() ?? null,
      payoutDetails: details
        ? {
            method: details.method,
            display: details.display,
            verifiedAt: details.verifiedAt?.toISOString() ?? null,
            changedAt: details.changedAt.toISOString(),
          }
        : null,
      codes: codes.map(toReferralCode),
      referralCount: referrals.length,
      statusHistory: history.map((h) => ({
        action: h.action,
        at: h.at.toISOString(),
        actorId: h.actorId,
        reason: h.reason,
      })),
    };
  }
}
