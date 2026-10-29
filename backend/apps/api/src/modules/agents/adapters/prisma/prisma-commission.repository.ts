/**
 * `CommissionRepository` on the `commissions` table.
 *
 * The conditional methods are single statements with the expected state in
 * the `WHERE` (`transition`, `attachToPayout`, `releaseFromPayout`,
 * `markPaidForPayout`), so Postgres decides a race: of two callers moving the
 * same commission, one changes the row and the other gets `null` / a count of
 * zero. Nothing here reads a row, decides, then writes it.
 */
import type { PrismaClient } from '@app/database';
import {
  OPEN_COMMISSION_STATUSES,
  type CommissionChanges,
  type CommissionListFilter,
  type CommissionPageCursor,
  type CommissionRecord,
  type CommissionRepository,
  type CommissionStatusValue,
} from '../../ports/agent-commission-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';
import {
  withConflictMapping,
  type UniqueViolationRule,
} from './prisma-unique-violation';

export const COMMISSION_UNIQUE_RULES: readonly UniqueViolationRule[] = [
  { constraint: 'commissions_pkey', fields: ['id'], reason: 'DUPLICATE_ID' },
  {
    constraint: 'commissions_attribution_id_key',
    fields: ['attribution_id'],
    reason: 'DUPLICATE_COMMISSION',
  },
  {
    constraint: 'commissions_payment_id_key',
    fields: ['payment_id'],
    reason: 'DUPLICATE_COMMISSION',
  },
  {
    constraint: 'commissions_phone_hash_key',
    fields: ['phone_hash'],
    reason: 'DUPLICATE_COMMISSION',
  },
];

interface CommissionRow {
  id: string;
  agentId: string;
  attributionId: string;
  paymentId: string;
  phoneHash: string;
  policyVersionId: string;
  status: CommissionStatusValue;
  calcType: 'PERCENTAGE';
  ruleValue: number;
  basePaise: number | null;
  amountPaise: number | null;
  amountPaidPaise: number;
  taxableAmountPaise: number;
  refundedPaise: number;
  preRefundAmountPaise: number | null;
  creditedPaise: number;
  reversedPaise: number;
  holdUntil: Date;
  reviewReasons: string[];
  approvedAt: Date | null;
  paidAt: Date | null;
  cancelledAt: Date | null;
  payoutId: string | null;
  createdAt: Date;
}

function toRecord(row: CommissionRow): CommissionRecord {
  return {
    id: row.id,
    agentId: row.agentId,
    attributionId: row.attributionId,
    paymentId: row.paymentId,
    phoneHash: row.phoneHash,
    policyVersionId: row.policyVersionId,
    status: row.status,
    calcType: row.calcType,
    ruleValue: row.ruleValue,
    basePaise: row.basePaise,
    amountPaise: row.amountPaise,
    amountPaidPaise: row.amountPaidPaise,
    taxableAmountPaise: row.taxableAmountPaise,
    refundedPaise: row.refundedPaise,
    preRefundAmountPaise: row.preRefundAmountPaise,
    creditedPaise: row.creditedPaise,
    reversedPaise: row.reversedPaise,
    holdUntil: row.holdUntil,
    reviewReasons: [...row.reviewReasons],
    approvedAt: row.approvedAt,
    paidAt: row.paidAt,
    cancelledAt: row.cancelledAt,
    payoutId: row.payoutId,
    createdAt: row.createdAt,
  };
}

const changesData = (changes: CommissionChanges) => ({
  status: changes.status,
  basePaise: changes.basePaise,
  amountPaise: changes.amountPaise,
  refundedPaise: changes.refundedPaise,
  preRefundAmountPaise: changes.preRefundAmountPaise,
  creditedPaise: changes.creditedPaise,
  reversedPaise: changes.reversedPaise,
  reviewReasons: changes.reviewReasons,
  approvedAt: changes.approvedAt,
  paidAt: changes.paidAt,
  cancelledAt: changes.cancelledAt,
});

export class PrismaCommissionRepository implements CommissionRepository {
  constructor(private readonly prisma: PrismaClient) {}

  create(
    commission: CommissionRecord,
    tx?: AgentTx,
  ): Promise<CommissionRecord> {
    return withConflictMapping(COMMISSION_UNIQUE_RULES, async () => {
      const row = await dbFor(this.prisma, tx).commission.create({
        data: {
          id: commission.id,
          agentId: commission.agentId,
          attributionId: commission.attributionId,
          paymentId: commission.paymentId,
          phoneHash: commission.phoneHash,
          policyVersionId: commission.policyVersionId,
          status: commission.status,
          calcType: commission.calcType,
          ruleValue: commission.ruleValue,
          basePaise: commission.basePaise,
          amountPaise: commission.amountPaise,
          amountPaidPaise: commission.amountPaidPaise,
          taxableAmountPaise: commission.taxableAmountPaise,
          refundedPaise: commission.refundedPaise,
          preRefundAmountPaise: commission.preRefundAmountPaise,
          creditedPaise: commission.creditedPaise,
          reversedPaise: commission.reversedPaise,
          holdUntil: commission.holdUntil,
          reviewReasons: commission.reviewReasons,
          approvedAt: commission.approvedAt,
          paidAt: commission.paidAt,
          cancelledAt: commission.cancelledAt,
          payoutId: commission.payoutId,
          createdAt: commission.createdAt,
        },
      });
      return toRecord(row);
    });
  }

  async findById(id: string, tx?: AgentTx): Promise<CommissionRecord | null> {
    const row = await dbFor(this.prisma, tx).commission.findUnique({
      where: { id },
    });
    return row ? toRecord(row) : null;
  }

  async findByPaymentId(
    paymentId: string,
    tx?: AgentTx,
  ): Promise<CommissionRecord | null> {
    const row = await dbFor(this.prisma, tx).commission.findUnique({
      where: { paymentId },
    });
    return row ? toRecord(row) : null;
  }

  async findByPhoneHash(
    phoneHash: string,
    tx?: AgentTx,
  ): Promise<CommissionRecord | null> {
    const row = await dbFor(this.prisma, tx).commission.findUnique({
      where: { phoneHash },
    });
    return row ? toRecord(row) : null;
  }

  async findByAttributionId(
    attributionId: string,
    tx?: AgentTx,
  ): Promise<CommissionRecord | null> {
    const row = await dbFor(this.prisma, tx).commission.findUnique({
      where: { attributionId },
    });
    return row ? toRecord(row) : null;
  }

  async update(
    id: string,
    changes: CommissionChanges,
    tx?: AgentTx,
  ): Promise<CommissionRecord> {
    try {
      const row = await dbFor(this.prisma, tx).commission.update({
        where: { id },
        data: changesData(changes),
      });
      return toRecord(row);
    } catch (error) {
      if ((error as { code?: unknown }).code === 'P2025') {
        throw new Error(`Unknown commission ${id}`);
      }
      throw error;
    }
  }

  async transition(
    id: string,
    from: CommissionStatusValue,
    changes: CommissionChanges,
    tx?: AgentTx,
  ): Promise<CommissionRecord | null> {
    const db = dbFor(this.prisma, tx);
    // One conditional statement: the state check and the write cannot be
    // separated by another request.
    const { count } = await db.commission.updateMany({
      where: { id, status: from },
      data: changesData(changes),
    });
    if (count === 0) return null;
    return this.findById(id, tx);
  }

  async listOpen(
    page: { limit: number; afterId?: string },
    tx?: AgentTx,
  ): Promise<CommissionRecord[]> {
    const rows = await dbFor(this.prisma, tx).commission.findMany({
      where: {
        status: { in: [...OPEN_COMMISSION_STATUSES] },
        ...(page.afterId !== undefined && { id: { gt: page.afterId } }),
      },
      orderBy: { id: 'asc' },
      take: page.limit,
    });
    return rows.map(toRecord);
  }

  async listAgentIdsWithPayable(
    input: { afterAgentId?: string; limit: number },
    tx?: AgentTx,
  ): Promise<string[]> {
    const rows = await dbFor(this.prisma, tx).commission.findMany({
      where: {
        status: 'APPROVED',
        payoutId: null,
        ...(input.afterAgentId !== undefined && {
          agentId: { gt: input.afterAgentId },
        }),
      },
      distinct: ['agentId'],
      orderBy: { agentId: 'asc' },
      take: input.limit,
      select: { agentId: true },
    });
    return rows.map((r) => r.agentId);
  }

  async listPayableByAgent(
    agentId: string,
    tx?: AgentTx,
  ): Promise<CommissionRecord[]> {
    const rows = await dbFor(this.prisma, tx).commission.findMany({
      where: { agentId, status: 'APPROVED', payoutId: null },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });
    return rows.map(toRecord);
  }

  async listByPayout(
    payoutId: string,
    tx?: AgentTx,
  ): Promise<CommissionRecord[]> {
    const rows = await dbFor(this.prisma, tx).commission.findMany({
      where: { payoutId },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });
    return rows.map(toRecord);
  }

  async listPage(
    filter: CommissionListFilter,
    page: { limit: number; after?: CommissionPageCursor },
    tx?: AgentTx,
  ): Promise<CommissionRecord[]> {
    const { after } = page;
    const rows = await dbFor(this.prisma, tx).commission.findMany({
      where: {
        ...(filter.agentId !== undefined && { agentId: filter.agentId }),
        ...(filter.status !== undefined && { status: filter.status }),
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

  async attachToPayout(
    commissionIds: readonly string[],
    payoutId: string,
    tx?: AgentTx,
  ): Promise<number> {
    const { count } = await dbFor(this.prisma, tx).commission.updateMany({
      where: {
        id: { in: [...new Set(commissionIds)] },
        status: 'APPROVED',
        payoutId: null,
      },
      data: { payoutId },
    });
    return count;
  }

  async releaseFromPayout(payoutId: string, tx?: AgentTx): Promise<number> {
    const { count } = await dbFor(this.prisma, tx).commission.updateMany({
      where: { payoutId },
      data: { payoutId: null },
    });
    return count;
  }

  async markPaidForPayout(
    payoutId: string,
    at: Date,
    tx?: AgentTx,
  ): Promise<number> {
    const { count } = await dbFor(this.prisma, tx).commission.updateMany({
      where: { payoutId, status: 'APPROVED' },
      data: { status: 'PAID', paidAt: at },
    });
    return count;
  }
}
