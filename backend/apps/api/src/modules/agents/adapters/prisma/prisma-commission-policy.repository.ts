/**
 * `CommissionPolicyRepository` on `commission_policy_versions` and
 * `agents.commission_policy_id`. Versions are only ever added, so this class
 * reads them and never writes one; the one write is assigning an agent's own
 * policy.
 */
import type { PrismaClient } from '@app/database';
import type {
  CommissionPolicyRepository,
  CommissionPolicyVersionRecord,
} from '../../ports/agent-commission-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';

interface PolicyRow {
  id: string;
  version: number;
  calcType: 'PERCENTAGE';
  value: number;
  holdDays: number;
  effectiveFrom: Date;
}

const toRecord = (row: PolicyRow): CommissionPolicyVersionRecord => ({
  id: row.id,
  version: row.version,
  calcType: row.calcType,
  value: row.value,
  holdDays: row.holdDays,
  effectiveFrom: row.effectiveFrom,
});

export class PrismaCommissionPolicyRepository implements CommissionPolicyRepository {
  constructor(private readonly prisma: PrismaClient) {}

  async findById(
    id: string,
    tx?: AgentTx,
  ): Promise<CommissionPolicyVersionRecord | null> {
    const row = await dbFor(this.prisma, tx).commissionPolicyVersion.findUnique(
      {
        where: { id },
      },
    );
    return row ? toRecord(row) : null;
  }

  async findActive(
    at: Date,
    tx?: AgentTx,
  ): Promise<CommissionPolicyVersionRecord | null> {
    const row = await dbFor(this.prisma, tx).commissionPolicyVersion.findFirst({
      where: { effectiveFrom: { lte: at } },
      orderBy: { version: 'desc' },
    });
    return row ? toRecord(row) : null;
  }

  async findForAgent(
    agentId: string,
    at: Date,
    tx?: AgentTx,
  ): Promise<CommissionPolicyVersionRecord | null> {
    const agent = await dbFor(this.prisma, tx).agent.findUnique({
      where: { id: agentId },
      select: { commissionPolicy: true },
    });
    if (agent?.commissionPolicy) return toRecord(agent.commissionPolicy);
    return this.findActive(at, tx);
  }

  async assignToAgent(
    agentId: string,
    policyId: string | null,
    tx?: AgentTx,
  ): Promise<void> {
    await dbFor(this.prisma, tx).agent.update({
      where: { id: agentId },
      data: { commissionPolicyId: policyId },
    });
  }
}
