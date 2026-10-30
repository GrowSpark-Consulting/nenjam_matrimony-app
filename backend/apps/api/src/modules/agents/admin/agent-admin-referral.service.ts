/**
 * Admin operations on referrals (attributions): list one agent's referrals and
 * correct one. Same rules as `AgentAdminService`: permission first, in the
 * transaction; a reason on every mutation; the audit row in the same
 * transaction. The member's phone is only ever shown masked.
 */
import { AgentMoneyError } from '../errors/agent-money-error';
import type {
  AgentAttributionStatus,
  AgentRepository,
  ReferralAttributionRecord,
  ReferralAttributionRepository,
} from '../ports/agent-data-ports';
import type {
  AgentAuditPort,
  AgentPermissionPort,
} from '../ports/agent-platform-ports';
import type { AgentUnitOfWork } from '../ports/agent-unit-of-work.port';
import {
  PERM,
  decodeCursor,
  encodeCursor,
  pageLimit,
  requireId,
  requirePermission,
  requireReason,
  type AdminActor,
} from './agent-admin-support';

export interface AgentAdminReferralServiceDeps {
  uow: AgentUnitOfWork;
  agents: AgentRepository;
  attributions: ReferralAttributionRepository;
  permission: AgentPermissionPort;
  audit: AgentAuditPort;
}

export interface AdminReferral {
  id: string;
  agentId: string;
  memberId: string | null;
  codeId: string | null;
  source: ReferralAttributionRecord['source'];
  status: AgentAttributionStatus;
  needsReview: boolean;
  attributedAt: string;
  windowEndsAt: string;
}

export type ReferralCorrection =
  | { action: 'REASSIGN_AGENT'; agentId: string; reason: string }
  | { action: 'REJECT'; reason: string }
  | { action: 'CLEAR_REVIEW'; reason: string };

const toView = (a: ReferralAttributionRecord): AdminReferral => ({
  id: a.id,
  agentId: a.agentId,
  memberId: a.memberId,
  codeId: a.codeId,
  source: a.source,
  status: a.status,
  needsReview: a.needsReview,
  attributedAt: a.attributedAt.toISOString(),
  windowEndsAt: a.windowEndsAt.toISOString(),
});

export class AgentAdminReferralService {
  constructor(private readonly deps: AgentAdminReferralServiceDeps) {}

  /** Newest first. Filters by status and review flag. */
  async list(
    actor: AdminActor,
    agentId: string,
    query: {
      status?: AgentAttributionStatus;
      needsReview?: boolean;
      cursor?: string;
      limit?: number;
    } = {},
  ): Promise<{ items: AdminReferral[]; nextCursor: string | null }> {
    requireId('agentId', agentId);
    const limit = pageLimit(query.limit);
    const after = decodeCursor(query.cursor);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.attributionView,
        tx,
      );
      if ((await this.deps.agents.findById(agentId, tx)) === null) {
        throw new AgentMoneyError('AGENT_NOT_FOUND');
      }
      // The filters are not part of the repository's paging, so the rows are
      // filtered here and then paged: an agent's referrals are few.
      const rows = (await this.deps.attributions.listByAgent(agentId, tx))
        .filter(
          (r) =>
            (query.status === undefined || r.status === query.status) &&
            (query.needsReview === undefined ||
              r.needsReview === query.needsReview),
        )
        .sort(
          (a, b) =>
            b.attributedAt.getTime() - a.attributedAt.getTime() ||
            (a.id < b.id ? 1 : a.id > b.id ? -1 : 0),
        )
        .filter(
          (r) =>
            after === undefined ||
            r.attributedAt.getTime() < after.at.getTime() ||
            (r.attributedAt.getTime() === after.at.getTime() &&
              r.id < after.id),
        );
      const page = rows.slice(0, limit);
      const last = page[page.length - 1];
      return {
        items: page.map(toView),
        nextCursor:
          rows.length > limit && last
            ? encodeCursor({ at: last.attributedAt, id: last.id })
            : null,
      };
    });
  }

  /**
   * - REASSIGN_AGENT: credit another agent; the target must be ACTIVE; the
   *   source becomes ADMIN_SET; the credit window end is not reset; refused
   *   when the target's phone is the member's phone. The old code belonged to
   *   the old agent, so the code link is cleared.
   * - REJECT: the referral stops counting.
   * - CLEAR_REVIEW: only the review flag.
   * Allowed while ACTIVE, EXPIRED or REJECTED; a CONVERTED referral has a
   * commission and is handled through the commission operations.
   */
  async correct(
    actor: AdminActor,
    attributionId: string,
    input: ReferralCorrection,
  ): Promise<AdminReferral> {
    requireId('id', attributionId);
    const reason = requireReason(input.reason);
    if (
      input.action !== 'REASSIGN_AGENT' &&
      input.action !== 'REJECT' &&
      input.action !== 'CLEAR_REVIEW'
    ) {
      throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['action'] });
    }
    if (input.action === 'REASSIGN_AGENT') requireId('agentId', input.agentId);

    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.attributionOverride,
        tx,
      );
      const current = await this.deps.attributions.findById(attributionId, tx);
      if (current === null) throw new AgentMoneyError('REFERRAL_NOT_FOUND');
      if (current.status === 'CONVERTED') {
        throw new AgentMoneyError('ATTRIBUTION_CONVERTED');
      }

      let changes: Parameters<ReferralAttributionRepository['correct']>[2];
      if (input.action === 'REASSIGN_AGENT') {
        const target = await this.deps.agents.findById(input.agentId, tx);
        if (target === null) throw new AgentMoneyError('AGENT_NOT_FOUND');
        if (target.status !== 'ACTIVE') {
          throw new AgentMoneyError('AGENT_STATUS_NOT_ALLOWED', {
            agentStatus: target.status,
          });
        }
        if (target.phoneHash === current.memberPhoneHash) {
          throw new AgentMoneyError('SELF_REFERRAL');
        }
        changes = { agentId: target.id, codeId: null, source: 'ADMIN_SET' };
      } else if (input.action === 'REJECT') {
        changes = { status: 'REJECTED' };
      } else {
        changes = { needsReview: false };
      }

      const updated = await this.deps.attributions.correct(
        attributionId,
        current.status,
        changes,
        tx,
      );
      if (updated === null) throw new AgentMoneyError('CONCURRENT_CHANGE');
      await this.deps.audit.record(
        {
          actorId: actor.userId,
          action: 'attribution.correct',
          entity: 'ReferralAttribution',
          entityId: attributionId,
          reason,
          metadata: { correction: input.action },
          before: {
            agentId: current.agentId,
            status: current.status,
            source: current.source,
            needsReview: current.needsReview,
          },
          after: {
            agentId: updated.agentId,
            status: updated.status,
            source: updated.source,
            needsReview: updated.needsReview,
          },
        },
        tx,
      );
      return toView(updated);
    });
  }
}
