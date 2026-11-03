/**
 * The agent program's daily jobs, registered with Shaaz's `DailyJobRegistry`
 * (`POST /internal/jobs/daily`, run at 02:00 IST by GitHub Actions).
 *
 * Every job here catches up (it does everything that is due, however late the
 * run) and is safe to run twice: `runDailyApproval` approves every commission
 * whose hold has ended, and approving credits the ledger once per commission
 * (idempotency key `credit:<commissionId>`); `runDailyExpiry` closes every
 * client draft whose time has run out, each close conditional on the draft
 * still being open.
 *
 * Both are registered in `AgentsModule.onModuleInit`, whatever
 * AGENT_PROGRAM_ENABLED or `agent.clients_enabled` say: commissions must be
 * approved and client PII deleted on time even with the routes switched off.
 */
import { AGENT_CLIENT_EXPIRY_BATCH_SIZE } from '../clients/agent-client-draft.service';
import type { AgentClientExpiryService } from '../clients/agent-client-expiry.service';
import type { AgentCommissionApprovalService } from './agent-commission-approval.service';

export const AGENT_DAILY_APPROVAL_JOB = 'agent.daily_approval';

/** Agent-added clients: drafts that ran out are closed and their PII deleted. */
export const AGENT_CLIENT_DRAFT_EXPIRY_JOB = 'agent.client_draft_expiry';

/**
 * How many open commissions one page of the daily approval reads. It is a
 * page size, not a limit: the run keeps paging until none are left. The ONE
 * place it is set.
 */
export const AGENT_DAILY_APPROVAL_BATCH_SIZE = 500;

/** The part of `DailyJobRegistry` this needs (keeps the registry out of the agent code). */
export interface AgentDailyJobRegistry {
  register(name: string, run: (now: Date) => Promise<unknown>): void;
}

export function registerAgentDailyJobs(
  registry: AgentDailyJobRegistry,
  approval: Pick<AgentCommissionApprovalService, 'runDailyApproval'>,
  clientExpiry: Pick<AgentClientExpiryService, 'runDailyExpiry'>,
): void {
  registry.register(AGENT_DAILY_APPROVAL_JOB, (now) =>
    approval.runDailyApproval(now, AGENT_DAILY_APPROVAL_BATCH_SIZE),
  );
  registry.register(AGENT_CLIENT_DRAFT_EXPIRY_JOB, (now) =>
    clientExpiry.runDailyExpiry(now, AGENT_CLIENT_EXPIRY_BATCH_SIZE),
  );
}
