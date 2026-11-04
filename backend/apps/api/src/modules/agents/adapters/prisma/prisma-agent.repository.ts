/**
 * `AgentRepository` on the `agents` table (Phase 1 migration).
 *
 * Column names differ from the record in three places: `phoneE164` is
 * `phone`, `panSealed` is `pan_encrypted`, and the record has no
 * `updated_at` (Prisma maintains it). A new agent starts as
 * PENDING_APPROVAL through the column default; transition rules live in
 * `agent-status.ts`, not here.
 */
import { Prisma, type PrismaClient } from '@app/database';
import type {
  AgentListFilter,
  AgentRecord,
  AgentRepository,
  NewAgentRecord,
} from '../../ports/agent-data-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';
import {
  withConflictMapping,
  type UniqueViolationRule,
} from './prisma-unique-violation';

/** The unique constraints on `agents` and what the services call them. */
export const AGENT_UNIQUE_RULES: readonly UniqueViolationRule[] = [
  { constraint: 'agents_pkey', fields: ['id'], reason: 'DUPLICATE_ID' },
  {
    constraint: 'agents_phone_hash_key',
    fields: ['phone_hash'],
    reason: 'DUPLICATE_PHONE_HASH',
  },
  // The same person's phone, under a different hash.
  {
    constraint: 'agents_phone_key',
    fields: ['phone'],
    reason: 'DUPLICATE_PHONE_HASH',
  },
];

type AgentRow = Prisma.AgentGetPayload<object>;

function toRecord(row: AgentRow): AgentRecord {
  return {
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
}

export class PrismaAgentRepository implements AgentRepository {
  constructor(private readonly prisma: PrismaClient) {}

  async findById(id: string, tx?: AgentTx): Promise<AgentRecord | null> {
    const row = await dbFor(this.prisma, tx).agent.findUnique({
      where: { id },
    });
    return row ? toRecord(row) : null;
  }

  async listPage(
    filter: AgentListFilter,
    page: { limit: number; after?: { at: Date; id: string } },
    tx?: AgentTx,
  ): Promise<AgentRecord[]> {
    const { after } = page;
    const rows = await dbFor(this.prisma, tx).agent.findMany({
      where: {
        ...(filter.status !== undefined && { status: filter.status }),
        ...(filter.namePrefix !== undefined && {
          name: { startsWith: filter.namePrefix, mode: 'insensitive' as const },
        }),
        ...(filter.phoneHash !== undefined && { phoneHash: filter.phoneHash }),
        ...(filter.ids !== undefined && { id: { in: filter.ids } }),
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

  async findByPhoneHash(
    phoneHash: string,
    tx?: AgentTx,
  ): Promise<AgentRecord | null> {
    const row = await dbFor(this.prisma, tx).agent.findUnique({
      where: { phoneHash },
    });
    return row ? toRecord(row) : null;
  }

  create(agent: NewAgentRecord, tx?: AgentTx): Promise<AgentRecord> {
    return withConflictMapping(AGENT_UNIQUE_RULES, async () => {
      const row = await dbFor(this.prisma, tx).agent.create({
        data: {
          id: agent.id,
          phone: agent.phoneE164,
          phoneHash: agent.phoneHash,
          name: agent.name,
          city: agent.city,
          state: agent.state,
          panLast4: agent.panLast4,
          panEncrypted: agent.panSealed,
          createdAt: agent.createdAt,
        },
      });
      return toRecord(row);
    });
  }

  async update(
    id: string,
    changes: Parameters<AgentRepository['update']>[1],
    tx?: AgentTx,
  ): Promise<AgentRecord> {
    try {
      const row = await dbFor(this.prisma, tx).agent.update({
        where: { id },
        data: {
          name: changes.name,
          city: changes.city,
          state: changes.state,
          status: changes.status,
          rejectionReason: changes.rejectionReason,
          approvedAt: changes.approvedAt,
          panLast4: changes.panLast4,
          panEncrypted: changes.panSealed,
          panVerifiedAt: changes.panVerifiedAt,
          payoutDetailsSet: changes.payoutDetailsSet,
        },
      });
      return toRecord(row);
    } catch (error) {
      // P2025: "record to update not found". The fake reports the same way.
      if (
        typeof error === 'object' &&
        error !== null &&
        (error as { code?: unknown }).code === 'P2025'
      ) {
        throw new Error(`Unknown agent ${id}`);
      }
      throw error;
    }
  }
}
