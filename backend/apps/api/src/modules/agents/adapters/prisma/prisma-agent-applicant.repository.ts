/**
 * `AgentApplicantRepository` on the `agent_applicants` table: the phone an
 * applicant verified, sealed, keyed by its hash. `save` is an upsert on the
 * `phone_hash` primary key. `find` returns the row even when it has expired
 * (the caller checks `expiresAt`). `delete` of an unknown hash is not an
 * error.
 *
 * Every `save` also purges a small batch of expired rows (see
 * `prisma-bounded-purge.ts`): rows whose `expires_at` is before
 * `now - graceMs`, oldest first, at most `batchSize`.
 */
import type { PrismaClient } from '@app/database';
import type {
  AgentApplicantRecord,
  AgentApplicantRepository,
} from '../../ports/agent-data-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';
import {
  checkPurgeOptions,
  runPurge,
  type BoundedPurgeOptions,
} from './prisma-bounded-purge';

export class PrismaAgentApplicantRepository implements AgentApplicantRepository {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly purge: BoundedPurgeOptions,
  ) {
    checkPurgeOptions(purge);
  }

  async save(record: AgentApplicantRecord, tx?: AgentTx): Promise<void> {
    const fields = {
      phoneSealed: record.phoneSealed,
      expiresAt: record.expiresAt,
    };
    await dbFor(this.prisma, tx).agentApplicant.upsert({
      where: { phoneHash: record.phoneHash },
      create: { phoneHash: record.phoneHash, ...fields },
      update: fields,
    });
    await this.purgeExpired(record.phoneHash);
  }

  async find(
    phoneHash: string,
    tx?: AgentTx,
  ): Promise<AgentApplicantRecord | null> {
    const row = await dbFor(this.prisma, tx).agentApplicant.findUnique({
      where: { phoneHash },
    });
    return row
      ? {
          phoneHash: row.phoneHash,
          phoneSealed: row.phoneSealed,
          expiresAt: row.expiresAt,
        }
      : null;
  }

  async delete(phoneHash: string, tx?: AgentTx): Promise<void> {
    await dbFor(this.prisma, tx).agentApplicant.deleteMany({
      where: { phoneHash },
    });
  }

  /** Never removes `keep`, the row this write just stored. */
  private purgeExpired(keep: string): Promise<void> {
    return runPurge(this.purge, 'applicants', async (cutoff, batchSize) => {
      const expired = await this.prisma.agentApplicant.findMany({
        where: { expiresAt: { lt: cutoff }, phoneHash: { not: keep } },
        orderBy: { expiresAt: 'asc' },
        take: batchSize,
        select: { phoneHash: true },
      });
      if (expired.length === 0) return;
      await this.prisma.agentApplicant.deleteMany({
        where: {
          phoneHash: { in: expired.map((r) => r.phoneHash) },
          expiresAt: { lt: cutoff },
        },
      });
    });
  }
}
