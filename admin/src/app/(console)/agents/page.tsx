'use client';

import { RequirePermission } from '@/components/AppShell';
import { Card, PageHeader } from '@/components/ui';

/**
 * Agent approval and management. The screens are built against the agent
 * admin API, which the agent-program backend owns and has not shipped yet —
 * so this page says so instead of showing simulated data.
 */
export default function AgentsPage() {
  return (
    <RequirePermission permission="agent.view">
      <PageHeader
        title="Agents"
        description="Partner Program applications, approvals and agent management."
      />
      <Card title="Not available yet">
        <p>
          Agent approval, rejection, pausing and code replacement run on the agent admin
          API (<code>/admin/agents/*</code>), which is still being built. This page will
          list applications as soon as it is live — nothing here is simulated.
        </p>
        <p className="muted">
          Already in place: the <code>agent.*</code>, <code>attribution.*</code>,{' '}
          <code>commission.*</code> and <code>payout.*</code> permissions, staff sign-in and
          the audit log those actions will use.
        </p>
      </Card>
    </RequirePermission>
  );
}
