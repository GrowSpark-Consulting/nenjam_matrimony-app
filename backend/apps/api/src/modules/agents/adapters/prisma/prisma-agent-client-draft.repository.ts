/**
 * `AgentClientDraftRepository` on the `agent_client_drafts` table
 * (migration 20261103090000).
 *
 * - **Own-agent scoping.** Every agent-side read and write filters on the
 *   agent id IN THE QUERY, so another agent's draft is indistinguishable
 *   from a missing one. Never replace that with a lookup by id followed by
 *   an ownership check.
 * - **Conditional writes.** Edit, submit, discard, reject and close name the
 *   state they expect in their WHERE clause and report a lost race as
 *   null / false, never as an error. The table's trigger is the last line:
 *   a change it does not allow fails loudly (a bug, not a refusal).
 * - **Locks.** `lockAgent` and `lockWaitingForAccept` take a row lock
 *   (SELECT ... FOR UPDATE) by id only, then read the row's state with an
 *   ordinary query: after the lock, that read sees the latest committed row,
 *   and no timestamp is compared in raw SQL (so the session time zone never
 *   matters).
 * - The one-open-draft-per-agent-and-phone index is reported as
 *   DUPLICATE_OPEN_CLIENT_DRAFT.
 */
import type { Prisma, PrismaClient } from '@app/database';
import {
  OPEN_CLIENT_DRAFT_STATUSES,
  type AgentClientDraftRecord,
  type AgentClientDraftRepository,
  type ClientDraftClosedReason,
  type ClientDraftListFilter,
  type ClientDraftPageCursor,
  type NewAgentClientDraft,
} from '../../ports/agent-client-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor, unwrapTx } from './prisma-agent-tx';
import {
  withConflictMapping,
  type UniqueViolationRule,
} from './prisma-unique-violation';

export const CLIENT_DRAFT_UNIQUE_RULES: readonly UniqueViolationRule[] = [
  {
    constraint: 'agent_client_drafts_pkey',
    fields: ['id'],
    reason: 'DUPLICATE_ID',
  },
  {
    constraint: 'agent_client_drafts_one_open_per_agent_phone_uq',
    fields: ['agent_id', 'phone_hash'],
    reason: 'DUPLICATE_OPEN_CLIENT_DRAFT',
  },
];

type Row = Prisma.AgentClientDraftGetPayload<object>;

const OPEN = [...OPEN_CLIENT_DRAFT_STATUSES];

function toRecord(row: Row): AgentClientDraftRecord {
  return {
    id: row.id,
    agentId: row.agentId,
    status: row.status,
    phoneHash: row.phoneHash,
    phoneSealed: row.phoneSealed,
    phoneMasked: row.phoneMasked,
    displayName: row.displayName,
    detailsSealed: row.detailsSealed,
    expiresAt: row.expiresAt,
    submittedAt: row.submittedAt,
    acceptedAt: row.acceptedAt,
    closedAt: row.closedAt,
    closedReason: row.closedReason as ClientDraftClosedReason | null,
    memberId: row.memberId,
    attributionId: row.attributionId,
    createdAt: row.createdAt,
  };
}

/** The rows the agent sees in `status`: an overdue open draft counts as EXPIRED. */
function statusWhere(
  filter: ClientDraftListFilter,
): Prisma.AgentClientDraftWhereInput {
  const { status, now } = filter;
  switch (status) {
    case undefined:
      return {};
    case 'DRAFT':
    case 'WAITING_FOR_CLIENT':
      return { status, expiresAt: { gt: now } };
    case 'EXPIRED':
      return {
        OR: [
          { status: 'EXPIRED' },
          { status: { in: OPEN }, expiresAt: { lte: now } },
        ],
      };
    default:
      return { status };
  }
}

/** What closing a draft as EXPIRED writes: its PII goes. */
const closedAsExpired = (reason: ClientDraftClosedReason, now: Date) => ({
  status: 'EXPIRED' as const,
  closedAt: now,
  closedReason: reason,
  phoneSealed: null,
  detailsSealed: null,
});

export class PrismaAgentClientDraftRepository implements AgentClientDraftRepository {
  constructor(private readonly prisma: PrismaClient) {}

  create(
    draft: NewAgentClientDraft,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord> {
    return withConflictMapping(CLIENT_DRAFT_UNIQUE_RULES, async () =>
      toRecord(
        await dbFor(this.prisma, tx).agentClientDraft.create({
          data: { ...draft, status: 'DRAFT' },
        }),
      ),
    );
  }

  async findByIdForAgent(
    id: string,
    agentId: string,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    const row = await dbFor(this.prisma, tx).agentClientDraft.findFirst({
      where: { id, agentId },
    });
    return row ? toRecord(row) : null;
  }

  async listPageByAgent(
    agentId: string,
    filter: ClientDraftListFilter,
    page: { limit: number; after?: ClientDraftPageCursor },
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord[]> {
    const { after } = page;
    const rows = await dbFor(this.prisma, tx).agentClientDraft.findMany({
      where: {
        AND: [
          { agentId },
          statusWhere(filter),
          ...(after === undefined
            ? []
            : [
                {
                  OR: [
                    { createdAt: { lt: after.at } },
                    { createdAt: after.at, id: { lt: after.id } },
                  ],
                },
              ]),
        ],
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: page.limit,
    });
    return rows.map(toRecord);
  }

  countOpen(agentId: string, tx?: AgentTx): Promise<number> {
    return dbFor(this.prisma, tx).agentClientDraft.count({
      where: { agentId, status: { in: OPEN } },
    });
  }

  async lockAgent(agentId: string, tx: AgentTx): Promise<void> {
    await unwrapTx(tx)
      .$queryRaw`SELECT "id" FROM "agents" WHERE "id" = ${agentId} FOR UPDATE`;
  }

  async findOpenByAgentAndHashes(
    agentId: string,
    phoneHashes: readonly string[],
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    const row = await dbFor(this.prisma, tx).agentClientDraft.findFirst({
      where: {
        agentId,
        status: { in: OPEN },
        phoneHash: { in: [...phoneHashes] },
      },
    });
    return row ? toRecord(row) : null;
  }

  async wasRejectedBy(
    agentId: string,
    phoneHashes: readonly string[],
    tx?: AgentTx,
  ): Promise<boolean> {
    const row = await dbFor(this.prisma, tx).agentClientDraft.findFirst({
      where: {
        agentId,
        status: 'REJECTED',
        phoneHash: { in: [...phoneHashes] },
      },
      select: { id: true },
    });
    return row !== null;
  }

  updateDetails(
    id: string,
    agentId: string,
    changes: { displayName: string; detailsSealed: string },
    now: Date,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    return this.changeOne(
      { id, agentId, status: 'DRAFT', expiresAt: { gt: now } },
      changes,
      tx,
    );
  }

  submit(
    id: string,
    agentId: string,
    changes: { submittedAt: Date; expiresAt: Date },
    now: Date,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    return this.changeOne(
      { id, agentId, status: 'DRAFT', expiresAt: { gt: now } },
      { ...changes, status: 'WAITING_FOR_CLIENT' },
      tx,
    );
  }

  async discard(id: string, agentId: string, tx?: AgentTx): Promise<boolean> {
    const { count } = await dbFor(this.prisma, tx).agentClientDraft.deleteMany({
      where: { id, agentId, status: 'DRAFT' },
    });
    return count === 1;
  }

  async findForPhone(
    id: string,
    phoneHashes: readonly string[],
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    const row = await dbFor(this.prisma, tx).agentClientDraft.findFirst({
      where: { id, phoneHash: { in: [...phoneHashes] } },
    });
    return row ? toRecord(row) : null;
  }

  async listWaitingForHashes(
    phoneHashes: readonly string[],
    now: Date,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord[]> {
    const rows = await dbFor(this.prisma, tx).agentClientDraft.findMany({
      where: {
        status: 'WAITING_FOR_CLIENT',
        phoneHash: { in: [...phoneHashes] },
        expiresAt: { gt: now },
      },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });
    return rows.map(toRecord);
  }

  async lockWaitingForAccept(
    id: string,
    phoneHashes: readonly string[],
    now: Date,
    tx: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    const db = unwrapTx(tx);
    await db.$queryRaw`SELECT "id" FROM "agent_client_drafts" WHERE "id" = ${id} FOR UPDATE`;
    const row = await db.agentClientDraft.findFirst({
      where: {
        id,
        status: 'WAITING_FOR_CLIENT',
        phoneHash: { in: [...phoneHashes] },
        expiresAt: { gt: now },
      },
    });
    return row ? toRecord(row) : null;
  }

  async markAccepted(
    id: string,
    changes: { memberId: string; attributionId: string; acceptedAt: Date },
    tx: AgentTx,
  ): Promise<AgentClientDraftRecord> {
    const row = await this.changeOne(
      { id, status: 'WAITING_FOR_CLIENT' },
      {
        ...changes,
        status: 'ACCEPTED',
        phoneSealed: null,
        detailsSealed: null,
      },
      tx,
    );
    if (row === null) {
      throw new Error('Only a WAITING_FOR_CLIENT draft can be accepted.');
    }
    return row;
  }

  markRejected(
    id: string,
    phoneHashes: readonly string[],
    now: Date,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    return this.changeOne(
      {
        id,
        status: 'WAITING_FOR_CLIENT',
        phoneHash: { in: [...phoneHashes] },
        expiresAt: { gt: now },
      },
      // The sealed phone stays: it is the lasting "never again" block.
      { status: 'REJECTED', closedAt: now, detailsSealed: null },
      tx,
    );
  }

  async close(
    id: string,
    reason: ClientDraftClosedReason,
    now: Date,
    tx?: AgentTx,
  ): Promise<boolean> {
    const { count } = await dbFor(this.prisma, tx).agentClientDraft.updateMany({
      where: { id, status: { in: OPEN } },
      data: closedAsExpired(reason, now),
    });
    return count === 1;
  }

  closeOthersForPhone(
    phoneHashes: readonly string[],
    exceptId: string,
    reason: ClientDraftClosedReason,
    now: Date,
    tx?: AgentTx,
  ): Promise<string[]> {
    return this.closeMatching(
      {
        id: { not: exceptId },
        status: { in: OPEN },
        phoneHash: { in: [...phoneHashes] },
      },
      reason,
      now,
      tx,
    );
  }

  async expireDue(
    agentId: string | null,
    now: Date,
    limit: number,
    tx?: AgentTx,
  ): Promise<string[]> {
    const db = dbFor(this.prisma, tx);
    const due = await db.agentClientDraft.findMany({
      where: {
        ...(agentId !== null && { agentId }),
        status: { in: OPEN },
        expiresAt: { lte: now },
      },
      orderBy: [{ expiresAt: 'asc' }, { id: 'asc' }],
      take: limit,
      select: { id: true },
    });
    const ids = due.map((d) => d.id);
    if (ids.length === 0) return [];
    // Conditional again: a draft accepted or rejected since the read stays.
    const closed = await this.closeMatching(
      { id: { in: ids }, status: { in: OPEN }, expiresAt: { lte: now } },
      'TIMED_OUT',
      now,
      tx,
    );
    return ids.filter((id) => closed.includes(id));
  }

  async closeOfTerminatedAgents(
    now: Date,
    limit: number,
    tx?: AgentTx,
  ): Promise<string[]> {
    const db = dbFor(this.prisma, tx);
    const open = await db.agentClientDraft.findMany({
      where: { status: { in: OPEN }, agent: { status: 'TERMINATED' } },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
      take: limit,
      select: { id: true },
    });
    if (open.length === 0) return [];
    return this.closeMatching(
      { id: { in: open.map((o) => o.id) }, status: { in: OPEN } },
      'AGENT_TERMINATED',
      now,
      tx,
    );
  }

  private async closeMatching(
    where: Prisma.AgentClientDraftWhereInput,
    reason: ClientDraftClosedReason,
    now: Date,
    tx?: AgentTx,
  ): Promise<string[]> {
    const rows = await dbFor(
      this.prisma,
      tx,
    ).agentClientDraft.updateManyAndReturn({
      where,
      data: closedAsExpired(reason, now),
      select: { id: true },
    });
    return rows.map((r) => r.id);
  }

  /** One conditional update by id; null when the row was not in the expected state. */
  private async changeOne(
    where: Prisma.AgentClientDraftWhereInput & { id: string },
    data: Prisma.AgentClientDraftUpdateManyMutationInput,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    const db = dbFor(this.prisma, tx);
    const { count } = await db.agentClientDraft.updateMany({ where, data });
    if (count === 0) return null;
    const row = await db.agentClientDraft.findUnique({
      where: { id: where.id },
    });
    return row ? toRecord(row) : null;
  }
}
