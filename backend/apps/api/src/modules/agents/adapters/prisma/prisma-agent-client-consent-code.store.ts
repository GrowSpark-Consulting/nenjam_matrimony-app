/**
 * `AgentClientConsentCodeStore` on `agent_client_consent_codes`: the newest
 * one-time code sent to a client's phone, one row per phone hash. Only an
 * id is kept (the OTP service holds the hashed code and purges its own
 * rows); the pointers that ran out are purged by the daily client expiry.
 */
import type { PrismaClient } from '@app/database';
import type {
  AgentClientConsentCodeRecord,
  AgentClientConsentCodeStore,
} from '../../ports/agent-client-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';

export class PrismaAgentClientConsentCodeStore implements AgentClientConsentCodeStore {
  constructor(private readonly prisma: PrismaClient) {}

  async save(
    record: AgentClientConsentCodeRecord,
    tx?: AgentTx,
  ): Promise<void> {
    const data = {
      challengeId: record.challengeId,
      expiresAt: record.expiresAt,
    };
    await dbFor(this.prisma, tx).agentClientConsentCode.upsert({
      where: { phoneHash: record.phoneHash },
      create: { phoneHash: record.phoneHash, ...data },
      update: data,
    });
  }

  async find(
    phoneHashes: readonly string[],
    tx?: AgentTx,
  ): Promise<AgentClientConsentCodeRecord | null> {
    const rows = await dbFor(this.prisma, tx).agentClientConsentCode.findMany({
      where: { phoneHash: { in: [...phoneHashes] } },
    });
    for (const hash of phoneHashes) {
      const row = rows.find((r) => r.phoneHash === hash);
      if (row) {
        return {
          phoneHash: row.phoneHash,
          challengeId: row.challengeId,
          expiresAt: row.expiresAt,
        };
      }
    }
    return null;
  }

  async delete(phoneHashes: readonly string[], tx?: AgentTx): Promise<void> {
    await dbFor(this.prisma, tx).agentClientConsentCode.deleteMany({
      where: { phoneHash: { in: [...phoneHashes] } },
    });
  }

  async purgeExpired(
    before: Date,
    limit: number,
    tx?: AgentTx,
  ): Promise<number> {
    const db = dbFor(this.prisma, tx);
    const stale = await db.agentClientConsentCode.findMany({
      where: { expiresAt: { lt: before } },
      orderBy: { expiresAt: 'asc' },
      take: limit,
      select: { phoneHash: true },
    });
    if (stale.length === 0) return 0;
    const { count } = await db.agentClientConsentCode.deleteMany({
      where: { phoneHash: { in: stale.map((s) => s.phoneHash) } },
    });
    return count;
  }
}
