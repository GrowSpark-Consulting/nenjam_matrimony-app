/**
 * `AgentPayoutDetailsRepository` on the `agent_payout_details` table: at
 * most one row per agent (the agent id is the primary key), so `save` is an
 * upsert. `detailsSealed` is already sealed by `AgentSecretSealer`; this
 * class stores and returns it as given and never sees the plain details.
 */
import type { PrismaClient } from '@app/database';
import type {
  AgentPayoutDetailsRecord,
  AgentPayoutDetailsRepository,
} from '../../ports/agent-data-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';

export class PrismaAgentPayoutDetailsRepository implements AgentPayoutDetailsRepository {
  constructor(private readonly prisma: PrismaClient) {}

  async find(
    agentId: string,
    tx?: AgentTx,
  ): Promise<AgentPayoutDetailsRecord | null> {
    const row = await dbFor(this.prisma, tx).agentPayoutDetails.findUnique({
      where: { agentId },
    });
    return row
      ? {
          agentId: row.agentId,
          method: row.method,
          detailsSealed: row.detailsSealed,
          display: row.display,
          verifiedAt: row.verifiedAt,
          changedAt: row.changedAt,
        }
      : null;
  }

  async save(record: AgentPayoutDetailsRecord, tx?: AgentTx): Promise<void> {
    const fields = {
      method: record.method,
      detailsSealed: record.detailsSealed,
      display: record.display,
      verifiedAt: record.verifiedAt,
      changedAt: record.changedAt,
    };
    await dbFor(this.prisma, tx).agentPayoutDetails.upsert({
      where: { agentId: record.agentId },
      create: { agentId: record.agentId, ...fields },
      update: fields,
    });
  }
}
