'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { Card, ErrorState, Loading, PageHeader } from '@/components/ui';
import { formatDateTime, formatPaise, humanize } from '@/lib/format';
import { can, homeFor } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type { Overview } from '@/lib/types';
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

function Dashboard() {
  const { me } = useSession();
  const { data, error, loading, reload } = useApi(
    (api) => api.get<Overview>('/admin/overview'),
    [],
  );

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
                <li key={status}>
                  <span>{humanize(status)}</span>
                  <span>{count.toLocaleString('en-IN')}</span>
                </li>
              ))}
            </ul>
          </Card>
          <Card title="Active paid memberships">
            <ul className="kv">
              {data.activeSubscriptions.map((plan) => (
                <li key={plan.planCode}>
                  <span>{plan.planName}</span>
                  <span>{plan.count.toLocaleString('en-IN')}</span>
                </li>
              ))}
            </ul>
          </Card>
          <Card
            title="Plan changes"
            actions={
              can(me?.permissions, 'plan.view') ? <Link href="/plans/">Open plans</Link> : null
            }
          >
            <ul className="kv">
              <li>
                <span>Drafts in progress</span>
                <span>{data.planDrafts.open}</span>
              </li>
              <li>
                <span>Awaiting a second admin’s approval</span>
                <span>{data.planDrafts.awaitingApproval}</span>
              </li>
            </ul>
          </Card>
          {data.revenueLast30Days ? (
            <Card title="Payments, last 30 days">
              <p className="stat">{formatPaise(data.revenueLast30Days.grossInPaise)}</p>
              <ul className="kv">
                <li>
                  <span>Successful payments</span>
                  <span>{data.revenueLast30Days.payments}</span>
                </li>
                <li>
                  <span>Refunded</span>
                  <span>{formatPaise(data.revenueLast30Days.refundedInPaise)}</span>
                </li>
              </ul>
            </Card>
          ) : null}
          <Card title="Agent program">
            <p className="muted">
              Agent metrics appear here once the agent admin API is live. Nothing is
              estimated in the meantime.
            </p>
          </Card>
        </div>
      ) : null}
    </>
  );
}
