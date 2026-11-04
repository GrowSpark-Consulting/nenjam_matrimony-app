/**
 * The daily job of agent-added clients (`agent.client_draft_expiry`, see
 * `registerAgentDailyJobs`):
 *
 * 1. every open draft (DRAFT or WAITING_FOR_CLIENT) whose `expires_at` has
 *    passed becomes EXPIRED (TIMED_OUT), and its sealed phone and details
 *    are deleted;
 * 2. every open draft of a TERMINATED agent becomes EXPIRED
 *    (AGENT_TERMINATED), its PII deleted the same way;
 * 3. the pointers to one-time codes that have run out are deleted.
 *
 * One audit row per closed draft, in the same transaction as the change.
 * It catches up (everything due, however many days late the run) and is
 * safe to run twice (each close is conditional on the draft still being
 * open). It does NOT check `agent.clients_enabled`: switching the feature
 * off must never keep PII past its time. Counts only in the result, never a
 * phone or a name.
 */
import type {
  AgentClientConsentCodeStore,
  AgentClientDraftRepository,
  ClientDraftClosedReason,
} from '../ports/agent-client-ports';
import type { AgentAuditPort } from '../ports/agent-platform-ports';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';
import { CLIENT_DRAFT_ENTITY } from './agent-client-draft.service';

export interface AgentClientExpiryDeps {
  drafts: Pick<
    AgentClientDraftRepository,
    'expireDue' | 'closeOfTerminatedAgents'
  >;
  codes: Pick<AgentClientConsentCodeStore, 'purgeExpired'>;
  uow: AgentUnitOfWork;
  audit: AgentAuditPort;
}

export interface AgentClientExpiryReport {
  expired: number;
  closedForTerminatedAgents: number;
  codesPurged: number;
}

export class AgentClientExpiryService {
  constructor(private readonly deps: AgentClientExpiryDeps) {}

  async runDailyExpiry(
    now: Date,
    batchSize: number,
  ): Promise<AgentClientExpiryReport> {
    if (!Number.isSafeInteger(batchSize) || batchSize < 1) {
      throw new RangeError('batchSize must be a positive integer.');
    }
    const expired = await this.closeAll(
      (tx) => this.deps.drafts.expireDue(null, now, batchSize, tx),
      'TIMED_OUT',
      batchSize,
    );
    const closedForTerminatedAgents = await this.closeAll(
      (tx) => this.deps.drafts.closeOfTerminatedAgents(now, batchSize, tx),
      'AGENT_TERMINATED',
      batchSize,
    );
    let codesPurged = 0;
    for (;;) {
      const purged = await this.deps.codes.purgeExpired(now, batchSize);
      codesPurged += purged;
      if (purged < batchSize) break;
    }
    return { expired, closedForTerminatedAgents, codesPurged };
  }

  /** Pages of closes, each page with its audit rows in one transaction. */
  private async closeAll(
    closePage: (tx: AgentTx) => Promise<string[]>,
    reason: ClientDraftClosedReason,
    batchSize: number,
  ): Promise<number> {
    let total = 0;
    for (;;) {
      const closed = await this.deps.uow.run(async (tx) => {
        const ids = await closePage(tx);
        for (const id of ids) {
          await this.deps.audit.record(
            {
              actorId: null,
              action: 'AGENT_CLIENT_DRAFT_EXPIRED',
              entity: CLIENT_DRAFT_ENTITY,
              entityId: id,
              metadata: { reason },
            },
            tx,
          );
        }
        return ids.length;
      });
      total += closed;
      if (closed < batchSize) return total;
    }
  }
}
