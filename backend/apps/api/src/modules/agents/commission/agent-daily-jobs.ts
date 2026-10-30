/**
 * The agent program's daily jobs, registered with Shaaz's `DailyJobRegistry`
 * (`POST /internal/jobs/daily`, run at 02:00 IST by GitHub Actions).
 *
 * Every job here catches up (it does everything that is due, however late the
 * run) and is safe to run twice: `runDailyApproval` approves every commission
 * whose hold has ended, and approving credits the ledger once per commission
 * (idempotency key `credit:<commissionId>`).
 */
import type { AgentCommissionApprovalService } from './agent-commission-approval.service';

export const AGENT_DAILY_APPROVAL_JOB = 'agent.daily_approval';

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
): void {
  registry.register(AGENT_DAILY_APPROVAL_JOB, (now) =>
    approval.runDailyApproval(now, AGENT_DAILY_APPROVAL_BATCH_SIZE),
  );
}
