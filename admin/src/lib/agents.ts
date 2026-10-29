import type { AgentStatus } from './types';

/** The order the status filter and summary list them in. */
export const AGENT_STATUSES: readonly AgentStatus[] = [
  'PENDING_APPROVAL',
  'ACTIVE',
  'SUSPENDED',
  'REJECTED',
  'TERMINATED',
];

const LABELS: Record<AgentStatus, string> = {
  PENDING_APPROVAL: 'awaiting approval',
  ACTIVE: 'active',
  // The agent program shows SUSPENDED as "Paused" everywhere.
  SUSPENDED: 'paused',
  REJECTED: 'rejected',
  TERMINATED: 'terminated',
};

export function agentStatusLabel(status: AgentStatus): string {
  return LABELS[status] ?? status.toLowerCase();
}

/** Approve and reject apply only to an application awaiting approval; the
 *  API refuses anything else (409 AGENT_TRANSITION_NOT_ALLOWED). */
export function canDecide(status: AgentStatus): boolean {
  return status === 'PENDING_APPROVAL';
}
