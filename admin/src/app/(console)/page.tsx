'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, type ReactNode } from 'react';
import { Card, ErrorState, Loading, PageHeader } from '@/components/ui';
import { AGENT_STATUSES, agentStatusLabel } from '@/lib/agents';
import { formatDateTime, formatPaise, humanize } from '@/lib/format';
import { agentsHref, subscriptionsHref } from '@/lib/links';
import { can, homeFor } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type { AgentsSummary, Overview } from '@/lib/types';
import { useApi } from '@/lib/use-api';

export default function OverviewPage() {
  const { me } = useSession();
  const router = useRouter();
  const allowed = can(me?.permissions, 'dashboard.view');

  useEffect(() => {
    // Admins without the dashboard land on their first section instead.
    if (me && !allowed) {
      const home = homeFor(me.permissions);
      if (home && home !== '/') router.replace(home);
    }
  }, [me, allowed, router]);

  if (!allowed) {
    return (
      <PageHeader
        title="Welcome"
        description="Your roles don’t include the overview. Use the menu to open a section."
      />
    );
  }
  return <Dashboard />;
}

/**
 * One label/number line. With [href] the whole line opens that page (already
 * filtered); without it, it is plain text. Links are only given when the admin
 * can open the page — the API checks again anyway.
 */
function Row({ label, value, href }: { label: ReactNode; value: ReactNode; href?: string | null }) {
  if (!href) {
    return (
      <li>
        <span>{label}</span>
        <span>{value}</span>
      </li>
    );
  }
  return (
    <li className="kv-row-link">
      <Link href={href} className="kv-link">
        <span>{label}</span>
        <span>
          {value} <span aria-hidden>›</span>
        </span>
      </Link>
    </li>
  );
}

function Dashboard() {
  const { me } = useSession();
  const { data, error, loading, reload } = useApi(
    (api) => api.get<Overview>('/admin/overview'),
    [],
  );
  const permissions = me?.permissions;
  const mayAgents = can(permissions, 'agent.view');
  const maySubscriptions = can(permissions, 'subscription.view');
  const mayPlans = can(permissions, 'plan.view');

  return (
    <>
      <PageHeader
        title="Overview"
        description={data ? `As of ${formatDateTime(data.generatedAt)}` : undefined}
      />
      {loading && !data ? <Loading /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {data ? (
        <div className="grid">
          <Card title="Members">
            <p className="stat">{data.members.total.toLocaleString('en-IN')}</p>
            <ul className="kv">
              {Object.entries(data.members.byStatus).map(([status, count]) => (
                <Row key={status} label={humanize(status)} value={count.toLocaleString('en-IN')} />
              ))}
            </ul>
          </Card>
          <Card
            title="Active paid memberships"
            actions={
              maySubscriptions ? (
                <Link href={subscriptionsHref({ status: 'ACTIVE' })}>Open subscriptions</Link>
              ) : null
            }
          >
            <ul className="kv">
              {data.activeSubscriptions.map((plan) => (
                <Row
                  key={plan.planCode}
                  label={plan.planName}
                  value={plan.count.toLocaleString('en-IN')}
                  href={
                    maySubscriptions
                      ? subscriptionsHref({ status: 'ACTIVE', plan: plan.planCode })
                      : null
                  }
                />
              ))}
            </ul>
          </Card>
          <Card
            title="Plan changes"
            actions={mayPlans ? <Link href="/plans/">Open plans</Link> : null}
          >
            <ul className="kv">
              <Row
                label="Drafts in progress"
                value={data.planDrafts.open}
                href={mayPlans ? '/plans/#drafts' : null}
              />
              <Row
                label="Awaiting a second admin’s approval"
                value={data.planDrafts.awaitingApproval}
                href={mayPlans ? '/plans/#drafts' : null}
              />
            </ul>
          </Card>
          {data.revenueLast30Days ? (
            <Card
              title="Payments, last 30 days"
              actions={
                maySubscriptions ? <Link href={subscriptionsHref()}>Open subscriptions</Link> : null
              }
            >
              <p className="stat">{formatPaise(data.revenueLast30Days.grossInPaise)}</p>
              <ul className="kv">
                <Row label="Successful payments" value={data.revenueLast30Days.payments} />
                <Row
                  label="Refunded"
                  value={formatPaise(data.revenueLast30Days.refundedInPaise)}
                />
              </ul>
              <p className="muted small">Each subscription shows its latest payment.</p>
            </Card>
          ) : null}
          {mayAgents ? <AgentProgramCard /> : null}
        </div>
      ) : null}
    </>
  );
}

/** Agents by status (each opens the Agents page on that status), from /admin/agents/summary. */
function AgentProgramCard() {
  const { me } = useSession();
  const summary = useApi((api) => api.get<AgentsSummary>('/admin/agents/summary'), []);
  const mayCommissions = can(me?.permissions, 'commission.view');
  const mayPayouts = can(me?.permissions, 'payout.view');

  return (
    <Card title="Agent program" actions={<Link href={agentsHref()}>Open agents</Link>}>
      {summary.loading && !summary.data ? <Loading /> : null}
      {summary.error ? <ErrorState message={summary.error} onRetry={summary.reload} /> : null}
      {summary.data ? (
        <>
          <ul className="kv">
            {AGENT_STATUSES.map((status) => (
              <Row
                key={status}
                label={agentStatusLabel(status)}
                value={(summary.data?.byStatus[status] ?? 0).toLocaleString('en-IN')}
                href={agentsHref(status)}
              />
            ))}
            <Row
              label="Payout details to verify"
              value={summary.data.payoutDetailsAwaitingVerification}
            />
            <Row label="Referrals needing review" value={summary.data.referralsNeedingReview} />
          </ul>
          {mayCommissions || mayPayouts ? (
            <p className="small">
              {mayCommissions ? <Link href="/commissions/">Commissions</Link> : null}
              {mayCommissions && mayPayouts ? ' · ' : null}
              {mayPayouts ? <Link href="/payouts/">Payouts</Link> : null}
            </p>
          ) : null}
        </>
      ) : null}
    </Card>
  );
}
