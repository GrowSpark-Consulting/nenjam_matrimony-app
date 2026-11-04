/**
 * Read-only queries the admin agent routes need beyond the repositories:
 * the list with its filters, the summary counts and the status history.
 * Masked data only: nothing here returns a sealed value.
 */
import type { AgentStatus } from '../agent/agent-status';
import type { AgentRecord } from './agent-data-ports';
import type { AgentTx } from './agent-unit-of-work.port';

export interface AdminAgentListFilter {
  status?: AgentStatus;
  /** Exactly these agent ids. */
  ids?: string[];
  /** Any of these phone hashes (one per active pepper version). */
  phoneHashes?: string[];
  /** Case-insensitive prefix of the agent's name. */
  namePrefix?: string;
}

/** An agent with what the list shows next to it. */
export interface AdminAgentRow {
  agent: AgentRecord;
  updatedAt: Date;
  /** The agent's primary referral code, or null before approval. */
  primaryCode: string | null;
  /** Payout details exist and an admin verified them. */
  payoutDetailsVerified: boolean;
}

export interface AdminAgentSummaryCounts {
  /** Every status present, zero if none. */
  byStatus: Record<AgentStatus, number>;
  /** Agents whose payout details are set but not verified. */
  payoutDetailsAwaitingVerification: number;
  referralsNeedingReview: number;
}

/** One status change, from the audit log (oldest first). */
export interface AgentStatusChange {
  from: AgentStatus;
  to: AgentStatus;
  at: Date;
  actorId: string | null;
  actorType: 'STAFF' | 'MEMBER' | 'AGENT' | 'SYSTEM';
  reason: string | null;
}

export interface AgentAdminReadPort {
  /** Newest first, ordered by (createdAt, id) descending, strictly after `after`. */
  listAgents(
    filter: AdminAgentListFilter,
    page: { limit: number; after?: { at: Date; id: string } },
    tx?: AgentTx,
  ): Promise<AdminAgentRow[]>;
  /** The row for one agent, or null. */
  findAgentRow(id: string, tx?: AgentTx): Promise<AdminAgentRow | null>;
  summary(tx?: AgentTx): Promise<AdminAgentSummaryCounts>;
  /**
   * Only this agent's status-change entries (`agent.approve`, `agent.reject`,
   * `agent.pause`, `agent.resume`, `agent.terminate`), so `agent.view` does
   * not grant the audit log.
   */
  statusHistory(agentId: string, tx?: AgentTx): Promise<AgentStatusChange[]>;
}
