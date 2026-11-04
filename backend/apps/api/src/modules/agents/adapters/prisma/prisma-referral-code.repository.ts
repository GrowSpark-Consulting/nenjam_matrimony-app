/**
 * `ReferralCodeRepository` on the `referral_codes` table.
 *
 * Two rules are enforced by the database, not by this class: the code format
 * (`referral_codes_code_format_chk`, a CHECK) and one primary code per agent
 * (`referral_codes_one_primary_per_agent_uq`, a partial unique index). A
 * badly formed code is a bug in the caller and surfaces as the raw database
 * error; it is not a conflict.
 */
import type { PrismaClient } from '@app/database';
import type {
  ReferralCodeRecord,
  ReferralCodeRepository,
} from '../../ports/agent-data-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';
import {
  withConflictMapping,
  type UniqueViolationRule,
} from './prisma-unique-violation';

export const REFERRAL_CODE_UNIQUE_RULES: readonly UniqueViolationRule[] = [
  { constraint: 'referral_codes_pkey', fields: ['id'], reason: 'DUPLICATE_ID' },
  {
    constraint: 'referral_codes_code_key',
    fields: ['code'],
    reason: 'DUPLICATE_CODE',
  },
  {
    constraint: 'referral_codes_one_primary_per_agent_uq',
    fields: ['agent_id'],
    reason: 'DUPLICATE_PRIMARY_CODE',
  },
];

interface CodeRow {
  id: string;
  agentId: string;
  code: string;
  isPrimary: boolean;
  isActive: boolean;
  createdAt: Date;
}

function toRecord(row: CodeRow): ReferralCodeRecord {
  return {
    id: row.id,
    agentId: row.agentId,
    code: row.code,
    isPrimary: row.isPrimary,
    isActive: row.isActive,
    createdAt: row.createdAt,
  };
}

export class PrismaReferralCodeRepository implements ReferralCodeRepository {
  constructor(private readonly prisma: PrismaClient) {}

  async findByCode(
    code: string,
    tx?: AgentTx,
  ): Promise<ReferralCodeRecord | null> {
    const row = await dbFor(this.prisma, tx).referralCode.findUnique({
      where: { code },
    });
    return row ? toRecord(row) : null;
  }

  /** Oldest first, so the order is the same every time. */
  async listByAgent(
    agentId: string,
    tx?: AgentTx,
  ): Promise<ReferralCodeRecord[]> {
    const rows = await dbFor(this.prisma, tx).referralCode.findMany({
      where: { agentId },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });
    return rows.map(toRecord);
  }

  async codeExists(code: string, tx?: AgentTx): Promise<boolean> {
    const row = await dbFor(this.prisma, tx).referralCode.findUnique({
      where: { code },
      select: { id: true },
    });
    return row !== null;
  }

  /**
   * Demote before promoting: the partial unique index allows one primary code
   * per agent, so promoting while another is primary is a DUPLICATE_PRIMARY_CODE.
   */
  setPrimary(
    id: string,
    isPrimary: boolean,
    tx?: AgentTx,
  ): Promise<ReferralCodeRecord> {
    return withConflictMapping(REFERRAL_CODE_UNIQUE_RULES, async () => {
      try {
        const row = await dbFor(this.prisma, tx).referralCode.update({
          where: { id },
          data: { isPrimary },
        });
        return toRecord(row);
      } catch (error) {
        if ((error as { code?: unknown }).code === 'P2025') {
          throw new Error(`Unknown referral code ${id}`);
        }
        throw error;
      }
    });
  }

  create(code: ReferralCodeRecord, tx?: AgentTx): Promise<ReferralCodeRecord> {
    return withConflictMapping(REFERRAL_CODE_UNIQUE_RULES, async () => {
      const row = await dbFor(this.prisma, tx).referralCode.create({
        data: {
          id: code.id,
          agentId: code.agentId,
          code: code.code,
          isPrimary: code.isPrimary,
          isActive: code.isActive,
          createdAt: code.createdAt,
        },
      });
      return toRecord(row);
    });
  }
}
