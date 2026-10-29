/**
 * `AgentPayoutRepository` on the `agent_payouts` table.
 *
 * `markPaid` and `cancel` are single conditional statements
 * (`WHERE id = ? AND status = 'CREATED'`): of two callers, one changes the
 * payout and the other gets `null`. One payout per agent and period (unless
 * cancelled) and a unique payment reference are enforced by unique indexes.
 */
import type { PrismaClient } from '@app/database';
import type {
  AgentPayoutListFilter,
  AgentPayoutRecord,
  AgentPayoutRepository,
} from '../../ports/agent-commission-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';
import {
  withConflictMapping,
  type UniqueViolationRule,
} from './prisma-unique-violation';

const PAYOUT_CREATE_RULES: readonly UniqueViolationRule[] = [
  { constraint: 'agent_payouts_pkey', fields: ['id'], reason: 'DUPLICATE_ID' },
  {
    constraint: 'agent_payouts_one_active_per_period_uq',
    fields: ['agent_id', 'period'],
    reason: 'DUPLICATE_PAYOUT',
  },
  {
    constraint: 'agent_payouts_reference_key',
    fields: ['reference'],
    reason: 'DUPLICATE_PAYOUT_REFERENCE',
  },
];

interface PayoutRow {
  id: string;
  agentId: string;
  period: string;
  amountPaise: number;
  taxWithheldPaise: number;
  netPaise: number;
  status: AgentPayoutRecord['status'];
  reference: string | null;
  paidAt: Date | null;
  cancelReason: string | null;
  cancelledAt: Date | null;
  createdBy: string;
  createdAt: Date;
}

const toRecord = (row: PayoutRow): AgentPayoutRecord => ({
  id: row.id,
  agentId: row.agentId,
  period: row.period,
  amountPaise: row.amountPaise,
  taxWithheldPaise: row.taxWithheldPaise,
  netPaise: row.netPaise,
  status: row.status,
  reference: row.reference,
  paidAt: row.paidAt,
  cancelReason: row.cancelReason,
  cancelledAt: row.cancelledAt,
  createdBy: row.createdBy,
  createdAt: row.createdAt,
});

export class PrismaAgentPayoutRepository implements AgentPayoutRepository {
  constructor(private readonly prisma: PrismaClient) {}

  create(payout: AgentPayoutRecord, tx?: AgentTx): Promise<AgentPayoutRecord> {
    return withConflictMapping(PAYOUT_CREATE_RULES, async () => {
      const row = await dbFor(this.prisma, tx).agentPayout.create({
        data: {
          id: payout.id,
          agentId: payout.agentId,
          period: payout.period,
          amountPaise: payout.amountPaise,
          taxWithheldPaise: payout.taxWithheldPaise,
          netPaise: payout.netPaise,
          status: payout.status,
          reference: payout.reference,
          paidAt: payout.paidAt,
          cancelReason: payout.cancelReason,
          cancelledAt: payout.cancelledAt,
          createdBy: payout.createdBy,
          createdAt: payout.createdAt,
        },
      });
      return toRecord(row);
    });
  }

  async findById(id: string, tx?: AgentTx): Promise<AgentPayoutRecord | null> {
    const row = await dbFor(this.prisma, tx).agentPayout.findUnique({
      where: { id },
    });
    return row ? toRecord(row) : null;
  }

  async findActiveByAgentPeriod(
    agentId: string,
    period: string,
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord | null> {
    const row = await dbFor(this.prisma, tx).agentPayout.findFirst({
      where: { agentId, period, status: { not: 'CANCELLED' } },
    });
    return row ? toRecord(row) : null;
  }

  async findByReference(
    reference: string,
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord | null> {
    const row = await dbFor(this.prisma, tx).agentPayout.findUnique({
      where: { reference },
    });
    return row ? toRecord(row) : null;
  }

  markPaid(
    id: string,
    paid: { reference: string; paidAt: Date },
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord | null> {
    return withConflictMapping(PAYOUT_CREATE_RULES, async () => {
      const db = dbFor(this.prisma, tx);
      const { count } = await db.agentPayout.updateMany({
        where: { id, status: 'CREATED' },
        data: {
          status: 'PAID',
          reference: paid.reference,
          paidAt: paid.paidAt,
        },
      });
      if (count === 0) return null;
      return this.findById(id, tx);
    });
  }

  async cancel(
    id: string,
    cancelled: { reason: string; at: Date },
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord | null> {
    const db = dbFor(this.prisma, tx);
    const { count } = await db.agentPayout.updateMany({
      where: { id, status: 'CREATED' },
      data: {
        status: 'CANCELLED',
        cancelReason: cancelled.reason,
        cancelledAt: cancelled.at,
      },
    });
    if (count === 0) return null;
    return this.findById(id, tx);
  }

  async listPage(
    filter: AgentPayoutListFilter,
    page: { limit: number; after?: { at: Date; id: string } },
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord[]> {
    const { after } = page;
    const rows = await dbFor(this.prisma, tx).agentPayout.findMany({
      where: {
        ...(filter.agentId !== undefined && { agentId: filter.agentId }),
        ...(filter.status !== undefined && { status: filter.status }),
        ...(filter.period !== undefined && { period: filter.period }),
        ...(after !== undefined && {
          OR: [
            { createdAt: { lt: after.at } },
            { createdAt: after.at, id: { lt: after.id } },
          ],
        }),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: page.limit,
    });
    return rows.map(toRecord);
  }
}
