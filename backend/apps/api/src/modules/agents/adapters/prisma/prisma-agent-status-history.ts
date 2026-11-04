/**
 * `AgentStatusHistoryPort` over `audit_logs` (Shaaz's audit table, read
 * only): the status-change entries of ONE agent and nothing else, oldest
 * first. Only the five status actions are read, so `agent.view` never shows
 * other audit rows (that needs `audit.view`).
 *
 * `AgentMemberProfilePort`: there is no member profile verification (KYC)
 * yet, so no member counts as verified. Consulted only while
 * `commission.require_verified_profile` is true, which the seed sets false.
 */
import type { PrismaClient } from '@app/database';
import type {
  AgentMemberProfilePort,
  AgentStatusHistoryPort,
} from '../../ports/agent-money-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';

export const AGENT_STATUS_ACTIONS = [
  'agent.approve',
  'agent.reject',
  'agent.pause',
  'agent.resume',
  'agent.terminate',
] as const;

export class PrismaAgentStatusHistory implements AgentStatusHistoryPort {
  constructor(private readonly prisma: PrismaClient) {}

  async listForAgent(agentId: string, tx?: AgentTx) {
    const rows = await dbFor(this.prisma, tx).auditLog.findMany({
      where: {
        entity: 'Agent',
        entityId: agentId,
        action: { in: [...AGENT_STATUS_ACTIONS] },
      },
      orderBy: { createdAt: 'asc' },
      select: { action: true, createdAt: true, actorId: true, reason: true },
    });
    return rows.map((r) => ({
      action: r.action,
      at: r.createdAt,
      actorId: r.actorId,
      reason: r.reason,
    }));
  }
}

export const NO_MEMBER_PROFILE_VERIFICATION: AgentMemberProfilePort = {
  isProfileVerified: () => Promise.resolve(false),
};
