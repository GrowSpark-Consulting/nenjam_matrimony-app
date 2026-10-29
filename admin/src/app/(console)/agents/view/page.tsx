'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { Suspense, useState } from 'react';
import { RequirePermission } from '@/components/AppShell';
import {
  Badge,
  Button,
  Card,
  ConfirmDialog,
  ErrorState,
  Loading,
  PageHeader,
  useToast,
} from '@/components/ui';
import { agentStatusLabel, canDecide } from '@/lib/agents';
import { formatDateTime, humanize } from '@/lib/format';
import { can } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type { AgentDetail } from '@/lib/types';
import { useApi } from '@/lib/use-api';

export default function AgentViewPage() {
  return (
    <RequirePermission permission="agent.view">
      <Suspense fallback={<Loading />}>
        <AgentView />
      </Suspense>
    </RequirePermission>
  );
}

function AgentView() {
  const id = useSearchParams().get('id') ?? '';
  const { api, me } = useSession();
  const toast = useToast();
  const agent = useApi((client) => client.get<AgentDetail>(`/admin/agents/${id}`), [id]);
  const [action, setAction] = useState<'approve' | 'reject' | null>(null);

  if (!id) return <ErrorState message="No agent id in the address." />;
  if (agent.loading && !agent.data) return <Loading />;
  if (agent.error) return <ErrorState message={agent.error} onRetry={agent.reload} />;
  const a = agent.data;
  if (!a) return null;

  const decide = canDecide(a.status) && can(me?.permissions, 'agent.approve');

  return (
    <>
      <PageHeader
        title={a.name}
        description={
          <>
            <Badge value={a.status} label={agentStatusLabel(a.status)} /> · {a.city}, {a.state} ·
            applied {formatDateTime(a.createdAt)}
          </>
        }
        actions={
          <div className="row-actions">
            <Link href="/agents/">Back</Link>
            {decide ? (
              <>
                <Button tone="primary" onClick={() => setAction('approve')}>
                  Approve
                </Button>
                <Button tone="danger" onClick={() => setAction('reject')}>
                  Reject
                </Button>
              </>
            ) : null}
          </div>
        }
      />

      {a.status === 'REJECTED' && a.rejectionReason ? (
        <Card title="Rejected">
          <p>{a.rejectionReason}</p>
          <p className="muted small">The applicant sees this reason and may apply again.</p>
        </Card>
      ) : null}

      <div className="grid">
        <Card title="Agent">
          <ul className="kv">
            <li>
              <span>Phone</span>
              <span>{a.phoneMasked}</span>
            </li>
            <li>
              <span>Place</span>
              <span>
                {a.city}, {a.state}
              </span>
            </li>
            <li>
              <span>Approved</span>
              <span>{formatDateTime(a.approvedAt)}</span>
            </li>
            <li>
              <span>Agent id</span>
              <code>{a.id}</code>
            </li>
          </ul>
        </Card>
        <Card title="PAN and payout">
          <ul className="kv">
            <li>
              <span>PAN</span>
              <span>
                {a.panOnFile ? `on file${a.panLast4 ? ` (…${a.panLast4})` : ''}` : 'not given'}
                {a.panVerifiedAt ? ` · verified ${formatDateTime(a.panVerifiedAt)}` : ''}
              </span>
            </li>
            <li>
              <span>Payout details</span>
              <span>
                {a.payoutDetails
                  ? `${a.payoutDetails.method} ${a.payoutDetails.display}`
                  : 'not set'}
              </span>
            </li>
            {a.payoutDetails ? (
              <li>
                <span>Payout verified</span>
                <span>
                  {a.payoutDetails.verifiedAt
                    ? formatDateTime(a.payoutDetails.verifiedAt)
                    : `no (changed ${formatDateTime(a.payoutDetails.changedAt)})`}
                </span>
              </li>
            ) : null}
          </ul>
        </Card>
      </div>

      <div className="grid">
        <Card title="Referral codes">
          {a.codes.length === 0 ? (
            <p className="muted">
              {a.status === 'PENDING_APPROVAL'
                ? 'The first code is issued on approval.'
                : 'No codes.'}
            </p>
          ) : (
            <ul className="kv">
              {a.codes.map((c) => (
                <li key={c.id}>
                  <code>{c.code}</code>
                  <span>
                    {c.isPrimary ? 'primary · ' : ''}
                    {c.isActive ? 'active' : 'inactive'} · {formatDateTime(c.createdAt)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <Card title="Referrals">
          <ul className="kv">
            <li>
              <span>Members referred</span>
              <span>{a.counts.referrals}</span>
            </li>
            {Object.entries(a.counts.byAttributionStatus).map(([status, count]) => (
              <li key={status}>
                <span>{humanize(status)}</span>
                <span>{count}</span>
              </li>
            ))}
            <li>
              <span>Needing review</span>
              <span>{a.counts.needsReview}</span>
            </li>
          </ul>
          <p className="muted small">Commissions appear here once the commission tables are live.</p>
        </Card>
      </div>

      <Card title="History">
        {a.statusHistory.length === 0 ? (
          <p className="muted">No status changes yet.</p>
        ) : (
          <ol className="timeline">
            {a.statusHistory.map((h, index) => (
              <li key={`${h.at}-${index}`}>
                <strong>
                  {agentStatusLabel(h.from)} → {agentStatusLabel(h.to)}
                </strong>{' '}
                <span className="muted">
                  {formatDateTime(h.at)} · {humanize(h.actorType)}
                </span>
                {h.reason ? <div>{h.reason}</div> : null}
              </li>
            ))}
          </ol>
        )}
      </Card>

      <ConfirmDialog
        open={action === 'approve'}
        title={`Approve ${a.name}?`}
        confirmLabel="Approve"
        requireReason
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          agent.setData(
            await api.post<AgentDetail>(`/admin/agents/${a.id}/approve`, { reason }),
          );
          toast('success', `${a.name} is approved and has a referral code.`);
        }}
      >
        <p>
          The agent becomes active and gets their first referral code (NM…), which they can
          share straight away.
        </p>
      </ConfirmDialog>

      <ConfirmDialog
        open={action === 'reject'}
        title={`Reject ${a.name}’s application?`}
        confirmLabel="Reject"
        tone="danger"
        requireReason
        reasonLabel="Reason (shown to the applicant, and kept in the audit log)"
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          agent.setData(
            await api.post<AgentDetail>(`/admin/agents/${a.id}/reject`, { reason }),
          );
          toast('success', 'Application rejected.');
        }}
      >
        <p>The applicant sees your reason and may apply again later.</p>
      </ConfirmDialog>
    </>
  );
}
