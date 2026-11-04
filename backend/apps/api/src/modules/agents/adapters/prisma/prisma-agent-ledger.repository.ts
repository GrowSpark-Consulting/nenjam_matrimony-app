/**
 * `AgentLedgerRepository` on the append-only `agent_ledger_entries` table.
 *
 * `append` uses `INSERT ... ON CONFLICT DO NOTHING` (Prisma's
 * `createMany({ skipDuplicates })`), so a replayed event with the same
 * idempotency key writes nothing, reports `{ inserted: false }` and, unlike
 * catching a unique violation, never aborts the caller's transaction. The
 * database trigger rejects any UPDATE or DELETE; this class has neither.
 */
import { Prisma, type PrismaClient } from '@app/database';
import type { LedgerEntry } from '../../commission/ledger-entries';
import type {
  AgentLedgerRepository,
  StoredLedgerEntry,
} from '../../ports/agent-commission-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';

interface LedgerRow {
  id: string;
  agentId: string;
  type: LedgerEntry['type'];
  amountPaise: number;
  idempotencyKey: string;
  commissionId: string | null;
  refundId: string | null;
  payoutId: string | null;
  calcType: string | null;
  ruleValue: number | null;
  ruleSnapshot: unknown;
  reason: string | null;
  createdAt: Date;
}

const toStored = (row: LedgerRow): StoredLedgerEntry => ({
  id: row.id,
  agentId: row.agentId,
  type: row.type,
  amountPaise: row.amountPaise,
  idempotencyKey: row.idempotencyKey,
  commissionId: row.commissionId,
  refundId: row.refundId,
  payoutId: row.payoutId,
  calcType: row.calcType,
  value: row.ruleValue,
  ruleSnapshot: row.ruleSnapshot,
  reason: row.reason,
  createdAt: row.createdAt,
});

export class PrismaAgentLedgerRepository implements AgentLedgerRepository {
  constructor(private readonly prisma: PrismaClient) {}

  async append(
    entry: LedgerEntry,
    tx?: AgentTx,
  ): Promise<{ inserted: boolean }> {
    const { count } = await dbFor(this.prisma, tx).agentLedgerEntry.createMany({
      data: [
        {
          agentId: entry.agentId,
          type: entry.type,
          amountPaise: entry.amountPaise,
          idempotencyKey: entry.idempotencyKey,
          commissionId: entry.commissionId,
          refundId: entry.refundId,
          payoutId: entry.payoutId,
          calcType: entry.calcType,
          ruleValue: entry.value,
          ruleSnapshot:
            entry.ruleSnapshot === null || entry.ruleSnapshot === undefined
              ? Prisma.DbNull
              : (entry.ruleSnapshot as Prisma.InputJsonValue),
          reason: entry.reason,
        },
      ],
      skipDuplicates: true,
    });
    return { inserted: count === 1 };
  }

  async findByKey(
    idempotencyKey: string,
    tx?: AgentTx,
  ): Promise<StoredLedgerEntry | null> {
    const row = await dbFor(this.prisma, tx).agentLedgerEntry.findUnique({
      where: { idempotencyKey },
    });
    return row ? toStored(row) : null;
  }

  async balance(agentId: string, tx?: AgentTx): Promise<number> {
    const result = await dbFor(this.prisma, tx).agentLedgerEntry.aggregate({
      where: { agentId },
      _sum: { amountPaise: true },
    });
    return result._sum.amountPaise ?? 0;
  }

  async listByAgent(
    agentId: string,
    tx?: AgentTx,
  ): Promise<StoredLedgerEntry[]> {
    const rows = await dbFor(this.prisma, tx).agentLedgerEntry.findMany({
      where: { agentId },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });
    return rows.map(toStored);
  }
}
