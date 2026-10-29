/**
 * In-memory `AgentAdminReadPort`, computed from the fake repositories and the
 * fake audit log so it always agrees with them. Tests only.
 */
import type { AgentStatus } from '../agent/agent-status';
import type {
  AdminAgentListFilter,
  AdminAgentRow,
  AdminAgentSummaryCounts,
  AgentAdminReadPort,
  AgentStatusChange,
} from '../ports/agent-admin-read.port';
import type {
  AgentPayoutDetailsRepository,
  AgentRecord,
  AgentRepository,
  ReferralAttributionRepository,
  ReferralCodeRepository,
} from '../ports/agent-data-ports';
import type { FakeAgentAudit } from './fake-agent-platform';

const STATUSES: AgentStatus[] = [
  'PENDING_APPROVAL',
  'ACTIVE',
  'REJECTED',
  'SUSPENDED',
  'TERMINATED',
];
const STATUS_ACTIONS = new Set([
  'agent.approve',
  'agent.reject',
  'agent.pause',
  'agent.resume',
  'agent.terminate',
]);

export class FakeAgentAdminRead implements AgentAdminReadPort {
  private readonly ids: string[] = [];
  private readonly updatedAt = new Map<string, Date>();
  /** How many attributions need review (set by a test). */
  referralsNeedingReview = 0;

  constructor(
    private readonly agents: AgentRepository,
    private readonly codes: ReferralCodeRepository,
    private readonly payoutDetails: AgentPayoutDetailsRepository,
    private readonly attributions: ReferralAttributionRepository,
    private readonly audit: FakeAgentAudit,
  ) {}

  /** Test helper: make an agent visible to the list and the summary. */
  track(id: string, updatedAt = new Date('2026-10-29T09:00:00.000Z')): void {
    if (!this.ids.includes(id)) this.ids.push(id);
    this.updatedAt.set(id, updatedAt);
  }

  async listAgents(
    filter: AdminAgentListFilter,
    page: { limit: number; after?: { at: Date; id: string } },
  ): Promise<AdminAgentRow[]> {
    const rows: AdminAgentRow[] = [];
    for (const id of this.ids) {
      const row = await this.findAgentRow(id);
      if (row && matches(row.agent, filter)) rows.push(row);
    }
    const { after } = page;
    return rows
      .sort(
        (a, b) =>
          b.agent.createdAt.getTime() - a.agent.createdAt.getTime() ||
          (a.agent.id < b.agent.id ? 1 : a.agent.id > b.agent.id ? -1 : 0),
      )
      .filter(
        (r) =>
          after === undefined ||
          r.agent.createdAt.getTime() < after.at.getTime() ||
          (r.agent.createdAt.getTime() === after.at.getTime() &&
            r.agent.id < after.id),
      )
      .slice(0, page.limit);
  }

  async findAgentRow(id: string): Promise<AdminAgentRow | null> {
    const agent = await this.agents.findById(id);
    if (agent === null) return null;
    const codes = await this.codes.listByAgent(id);
    const details = await this.payoutDetails.find(id);
    return {
      agent,
      updatedAt: this.updatedAt.get(id) ?? agent.createdAt,
      primaryCode: codes.find((c) => c.isPrimary)?.code ?? null,
      payoutDetailsVerified: details?.verifiedAt != null,
    };
  }

  async summary(): Promise<AdminAgentSummaryCounts> {
    const byStatus = Object.fromEntries(STATUSES.map((s) => [s, 0])) as Record<
      AgentStatus,
      number
    >;
    let payoutDetailsAwaitingVerification = 0;
    for (const id of this.ids) {
      const agent = await this.agents.findById(id);
      if (agent === null) continue;
      byStatus[agent.status] += 1;
      const details = await this.payoutDetails.find(id);
      if (details !== null && details.verifiedAt === null) {
        payoutDetailsAwaitingVerification += 1;
      }
    }
    return {
      byStatus,
      payoutDetailsAwaitingVerification,
      referralsNeedingReview: this.referralsNeedingReview,
    };
  }

  statusHistory(agentId: string): Promise<AgentStatusChange[]> {
    const history: AgentStatusChange[] = [];
    for (const e of this.audit.entries) {
      if (e.entity !== 'Agent' || e.entityId !== agentId) continue;
      if (!STATUS_ACTIONS.has(e.action)) continue;
      const from = e.before?.status as AgentStatus | undefined;
      const to = e.after?.status as AgentStatus | undefined;
      if (!from || !to) continue;
      history.push({
        from,
        to,
        at: new Date('2026-10-29T09:00:00.000Z'),
        actorId: e.actorId,
        actorType: e.actorType ?? 'STAFF',
        reason: e.reason ?? null,
      });
    }
    return Promise.resolve(history);
  }

  /** Keeps the attribution repository in the constructor for parity with the real one. */
  get attributionRepository(): ReferralAttributionRepository {
    return this.attributions;
  }
}

function matches(agent: AgentRecord, filter: AdminAgentListFilter): boolean {
  return (
    (filter.status === undefined || agent.status === filter.status) &&
    (filter.ids === undefined || filter.ids.includes(agent.id)) &&
    (filter.phoneHashes === undefined ||
      filter.phoneHashes.includes(agent.phoneHash)) &&
    (filter.namePrefix === undefined ||
      agent.name.toLowerCase().startsWith(filter.namePrefix.toLowerCase()))
  );
}
