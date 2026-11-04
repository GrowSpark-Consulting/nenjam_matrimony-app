/**
 * `AgentAdminReadPort` on the Phase 1 tables and `audit_logs`. Read only;
 * masked data only (the sealed PAN and payout details are never selected for
 * the caller, only used to answer "is it on file").
 */
import type { PrismaClient } from '@app/database';
import type { AgentStatus } from '../../agent/agent-status';
import type {
  AdminAgentListFilter,
  AdminAgentRow,
  AdminAgentSummaryCounts,
  AgentAdminReadPort,
  AgentStatusChange,
} from '../../ports/agent-admin-read.port';
import type { AgentRecord } from '../../ports/agent-data-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';

const STATUSES: readonly AgentStatus[] = [
  'PENDING_APPROVAL',
  'ACTIVE',
  'REJECTED',
  'SUSPENDED',
  'TERMINATED',
];

/** The audit actions that record a status change of an agent. */
export const AGENT_STATUS_ACTIONS = [
  'agent.approve',
  'agent.reject',
  'agent.pause',
  'agent.resume',
  'agent.terminate',
] as const;

const ACTOR_TYPES = new Set(['STAFF', 'MEMBER', 'AGENT', 'SYSTEM']);

interface AgentRowWithRelations {
  id: string;
  phone: string;
  phoneHash: string;
  name: string;
  city: string;
  state: string;
  status: AgentStatus;
  rejectionReason: string | null;
  approvedAt: Date | null;
  panLast4: string | null;
  panEncrypted: string | null;
  panVerifiedAt: Date | null;
  payoutDetailsSet: boolean;
  createdAt: Date;
  updatedAt: Date;
  referralCodes: Array<{ code: string }>;
  payoutDetails: { verifiedAt: Date | null } | null;
}

const include = {
  referralCodes: {
    where: { isPrimary: true },
    select: { code: true },
    take: 1,
  },
  payoutDetails: { select: { verifiedAt: true } },
} as const;

function toRow(row: AgentRowWithRelations): AdminAgentRow {
  const agent: AgentRecord = {
    id: row.id,
    phoneHash: row.phoneHash,
    phoneE164: row.phone,
    name: row.name,
    city: row.city,
    state: row.state,
    status: row.status,
    rejectionReason: row.rejectionReason,
    approvedAt: row.approvedAt,
    panLast4: row.panLast4,
    panSealed: row.panEncrypted,
    panVerifiedAt: row.panVerifiedAt,
    payoutDetailsSet: row.payoutDetailsSet,
    createdAt: row.createdAt,
  };
  return {
    agent,
    updatedAt: row.updatedAt,
    primaryCode: row.referralCodes[0]?.code ?? null,
    payoutDetailsVerified: row.payoutDetails?.verifiedAt != null,
  };
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const statusIn = (value: unknown): AgentStatus | null =>
  isRecord(value) &&
  typeof value.status === 'string' &&
  (STATUSES as readonly string[]).includes(value.status)
    ? (value.status as AgentStatus)
    : null;

export class PrismaAgentAdminRead implements AgentAdminReadPort {
  constructor(private readonly prisma: PrismaClient) {}

  async listAgents(
    filter: AdminAgentListFilter,
    page: { limit: number; after?: { at: Date; id: string } },
    tx?: AgentTx,
  ): Promise<AdminAgentRow[]> {
    const { after } = page;
    const rows = await dbFor(this.prisma, tx).agent.findMany({
      where: {
        ...(filter.status !== undefined && { status: filter.status }),
        ...(filter.ids !== undefined && { id: { in: filter.ids } }),
        ...(filter.phoneHashes !== undefined && {
          phoneHash: { in: filter.phoneHashes },
        }),
        ...(filter.namePrefix !== undefined && {
          name: { startsWith: filter.namePrefix, mode: 'insensitive' as const },
        }),
        ...(after !== undefined && {
          OR: [
            { createdAt: { lt: after.at } },
            { createdAt: after.at, id: { lt: after.id } },
          ],
        }),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: page.limit,
      include,
    });
    return rows.map(toRow);
  }

  async findAgentRow(id: string, tx?: AgentTx): Promise<AdminAgentRow | null> {
    const row = await dbFor(this.prisma, tx).agent.findUnique({
      where: { id },
      include,
    });
    return row ? toRow(row) : null;
  }

  async summary(tx?: AgentTx): Promise<AdminAgentSummaryCounts> {
    const db = dbFor(this.prisma, tx);
    const grouped = await db.agent.groupBy({
      by: ['status'],
      _count: { _all: true },
    });
    const byStatus = Object.fromEntries(
      STATUSES.map((status) => [status, 0]),
    ) as Record<AgentStatus, number>;
    for (const group of grouped) {
      byStatus[group.status] = group._count._all;
    }
    const [payoutDetailsAwaitingVerification, referralsNeedingReview] =
      await Promise.all([
        db.agentPayoutDetails.count({ where: { verifiedAt: null } }),
        db.referralAttribution.count({ where: { needsReview: true } }),
      ]);
    return {
      byStatus,
      payoutDetailsAwaitingVerification,
      referralsNeedingReview,
    };
  }

  async statusHistory(
    agentId: string,
    tx?: AgentTx,
  ): Promise<AgentStatusChange[]> {
    const rows = await dbFor(this.prisma, tx).auditLog.findMany({
      where: {
        entity: 'Agent',
        entityId: agentId,
        action: { in: [...AGENT_STATUS_ACTIONS] },
      },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
      select: {
        before: true,
        after: true,
        createdAt: true,
        actorId: true,
        actorType: true,
        reason: true,
      },
    });
    const history: AgentStatusChange[] = [];
    for (const row of rows) {
      const from = statusIn(row.before);
      const to = statusIn(row.after);
      // A row without both statuses is not a status change we can show.
      if (from === null || to === null) continue;
      history.push({
        from,
        to,
        at: row.createdAt,
        actorId: row.actorId,
        actorType: (row.actorType && ACTOR_TYPES.has(row.actorType)
          ? row.actorType
          : 'STAFF') as AgentStatusChange['actorType'],
        reason: row.reason,
      });
    }
    return history;
  }
}
