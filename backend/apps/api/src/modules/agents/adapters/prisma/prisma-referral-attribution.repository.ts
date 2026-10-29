/**
 * `ReferralAttributionRepository` on the `referral_attributions` table.
 *
 * - `memberId` is `user_id` and `attributedAt` is `created_at`. Both
 *   `user_id` and `code_id` are nullable (`ON DELETE SET NULL`): a deleted
 *   member or code leaves the row, and the record then says `null`.
 * - **Own-agent scoping.** `findByIdForAgent` filters on the agent id in the
 *   query itself, so another agent's row is indistinguishable from a missing
 *   one. Never replace it with a lookup by id followed by an ownership check.
 * - Pages are newest first, ordered by `(created_at, id)` descending, and the
 *   cursor compares the same pair, so a page boundary never skips or repeats
 *   a row that shares a timestamp.
 * - One attribution per member and per phone hash, enforced by the unique
 *   indexes; a violation is `DUPLICATE_ATTRIBUTION`. The record's phone hash
 *   is required (the column is NOT NULL).
 */
import type { PrismaClient } from '@app/database';
import type {
  AttributionPageCursor,
  ReferralAttributionRecord,
  ReferralAttributionRepository,
} from '../../ports/agent-data-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';
import {
  withConflictMapping,
  type UniqueViolationRule,
} from './prisma-unique-violation';

export const ATTRIBUTION_UNIQUE_RULES: readonly UniqueViolationRule[] = [
  {
    constraint: 'referral_attributions_pkey',
    fields: ['id'],
    reason: 'DUPLICATE_ATTRIBUTION',
  },
  {
    constraint: 'referral_attributions_user_id_key',
    fields: ['user_id'],
    reason: 'DUPLICATE_ATTRIBUTION',
  },
  {
    constraint: 'referral_attributions_phone_hash_key',
    fields: ['phone_hash'],
    reason: 'DUPLICATE_ATTRIBUTION',
  },
];

interface AttributionRow {
  id: string;
  userId: string | null;
  phoneHash: string;
  agentId: string;
  codeId: string | null;
  source: ReferralAttributionRecord['source'];
  status: ReferralAttributionRecord['status'];
  windowEndsAt: Date;
  needsReview: boolean;
  createdAt: Date;
}

function toRecord(row: AttributionRow): ReferralAttributionRecord {
  return {
    id: row.id,
    memberId: row.userId,
    agentId: row.agentId,
    codeId: row.codeId,
    source: row.source,
    memberPhoneHash: row.phoneHash,
    attributedAt: row.createdAt,
    status: row.status,
    windowEndsAt: row.windowEndsAt,
    needsReview: row.needsReview,
  };
}

export class PrismaReferralAttributionRepository implements ReferralAttributionRepository {
  constructor(private readonly prisma: PrismaClient) {}

  async findByMemberId(
    memberId: string,
    tx?: AgentTx,
  ): Promise<ReferralAttributionRecord | null> {
    const row = await dbFor(this.prisma, tx).referralAttribution.findUnique({
      where: { userId: memberId },
    });
    return row ? toRecord(row) : null;
  }

  /** Oldest first, so the order is the same every time. */
  async listByAgent(
    agentId: string,
    tx?: AgentTx,
  ): Promise<ReferralAttributionRecord[]> {
    const rows = await dbFor(this.prisma, tx).referralAttribution.findMany({
      where: { agentId },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });
    return rows.map(toRecord);
  }

  async listPageByAgent(
    agentId: string,
    page: { limit: number; after?: AttributionPageCursor },
    tx?: AgentTx,
  ): Promise<ReferralAttributionRecord[]> {
    const { after } = page;
    const rows = await dbFor(this.prisma, tx).referralAttribution.findMany({
      where: {
        agentId,
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

  async findByIdForAgent(
    attributionId: string,
    agentId: string,
    tx?: AgentTx,
  ): Promise<ReferralAttributionRecord | null> {
    const row = await dbFor(this.prisma, tx).referralAttribution.findFirst({
      where: { id: attributionId, agentId },
    });
    return row ? toRecord(row) : null;
  }

  async isPhoneHashCredited(phoneHash: string, tx?: AgentTx): Promise<boolean> {
    const row = await dbFor(this.prisma, tx).referralAttribution.findUnique({
      where: { phoneHash },
      select: { id: true },
    });
    return row !== null;
  }

  create(
    attribution: ReferralAttributionRecord,
    tx?: AgentTx,
  ): Promise<ReferralAttributionRecord> {
    // The column is NOT NULL; refuse early with a clear message.
    if (
      typeof attribution.memberPhoneHash !== 'string' ||
      attribution.memberPhoneHash === ''
    ) {
      return Promise.reject(
        new RangeError('An attribution needs a member phone hash.'),
      );
    }
    return withConflictMapping(ATTRIBUTION_UNIQUE_RULES, async () => {
      const row = await dbFor(this.prisma, tx).referralAttribution.create({
        data: {
          id: attribution.id,
          userId: attribution.memberId,
          phoneHash: attribution.memberPhoneHash,
          agentId: attribution.agentId,
          codeId: attribution.codeId,
          source: attribution.source,
          status: attribution.status,
          windowEndsAt: attribution.windowEndsAt,
          needsReview: attribution.needsReview,
          createdAt: attribution.attributedAt,
        },
      });
      return toRecord(row);
    });
  }
}
