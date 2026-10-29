'use client';

import Link from 'next/link';
import { useState } from 'react';
import { RequirePermission } from '@/components/AppShell';
import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  Loading,
  PageHeader,
} from '@/components/ui';
import { formatDate, formatPaise } from '@/lib/format';
import type { Page, SubscriptionRow } from '@/lib/types';
import { useApi } from '@/lib/use-api';

interface Filters {
  q: string;
  status: string;
  planCode: string;
}

export default function SubscriptionsPage() {
  return (
    <RequirePermission permission="subscription.view">
      <Subscriptions />
    </RequirePermission>
  );
}

function Subscriptions() {
  const [draft, setDraft] = useState<Filters>({ q: '', status: '', planCode: '' });
  const [filters, setFilters] = useState<Filters>(draft);
  const [cursors, setCursors] = useState<Array<string | null>>([null]);
  const cursor = cursors[cursors.length - 1] ?? null;

  const page = useApi(
    (api) =>
      api.get<Page<SubscriptionRow>>('/admin/subscriptions', {
        q: filters.q || undefined,
        status: filters.status || undefined,
        planCode: filters.planCode || undefined,
        cursor,
        limit: 25,
      }),
    [filters, cursor],
  );

  return (
    <>
      <PageHeader
        title="Subscriptions"
        description="Look up a member’s membership. Contact details are masked."
      />
      <Card>
        <form
          className="filters"
          onSubmit={(event) => {
            event.preventDefault();
            setCursors([null]);
            setFilters(draft);
          }}
        >
          <Field
            label="Member"
            hint="Exact email, phone (+91…), user id or subscription id. Leave empty to list all."
          >
            {(props) => (
              <input
                {...props}
                type="search"
                value={draft.q}
                onChange={(e) => setDraft({ ...draft, q: e.target.value })}
              />
            )}
          </Field>
          <Field label="Status">
            {(props) => (
              <select
                {...props}
                value={draft.status}
                onChange={(e) => setDraft({ ...draft, status: e.target.value })}
              >
                <option value="">Any</option>
                <option value="ACTIVE">Active</option>
                <option value="PENDING">Pending payment</option>
                <option value="EXPIRED">Expired</option>
                <option value="CANCELLED">Cancelled</option>
              </select>
            )}
          </Field>
          <Field label="Plan">
            {(props) => (
              <select
                {...props}
                value={draft.planCode}
                onChange={(e) => setDraft({ ...draft, planCode: e.target.value })}
              >
                <option value="">Any</option>
                <option value="GOLD">Gold</option>
                <option value="PLATINUM">Platinum</option>
                <option value="SILVER">Silver (legacy)</option>
              </select>
            )}
          </Field>
          <Button type="submit" tone="primary">
            Search
          </Button>
        </form>
      </Card>

      <Card>
        {page.loading && !page.data ? <Loading /> : null}
        {page.error ? <ErrorState message={page.error} onRetry={page.reload} /> : null}
        {page.data && page.data.items.length === 0 ? (
          <EmptyState title="No subscriptions found">
            {filters.q ? 'Check the identifier — search needs an exact match.' : null}
          </EmptyState>
        ) : null}
        {page.data && page.data.items.length > 0 ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">Member</th>
                  <th scope="col">Plan</th>
                  <th scope="col">Status</th>
                  <th scope="col">Period</th>
                  <th scope="col">Price</th>
                  <th scope="col">Last payment</th>
                </tr>
              </thead>
              <tbody>
                {page.data.items.map((row) => (
                  <tr key={row.id}>
                    <td>
                      <Link href={`/subscriptions/view/?id=${row.id}`}>
                        {row.member.name ?? row.member.email ?? row.member.phone ?? row.member.userId.slice(0, 8)}
                      </Link>
                      <div className="muted small">
                        {[row.member.email, row.member.phone].filter(Boolean).join(' · ')}
                      </div>
                    </td>
                    <td>
                      {row.plan.name}
                      {row.months ? <span className="muted small"> · {row.months} mo</span> : null}
                    </td>
                    <td>
                      <Badge value={row.status} />
                      {row.source === 'ADMIN_GRANT' ? (
                        <span className="muted small"> granted</span>
                      ) : null}
                    </td>
                    <td>
                      {formatDate(row.startDate)} – {formatDate(row.endDate)}
                    </td>
                    <td>{row.priceInPaise === null ? '—' : formatPaise(row.priceInPaise)}</td>
                    <td>
                      {row.lastPayment ? (
                        <>
                          <Badge value={row.lastPayment.status} />{' '}
                          {formatPaise(row.lastPayment.amountInPaise)}
                        </>
                      ) : (
                        '—'
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
        <div className="pager">
          <Button
            disabled={cursors.length <= 1 || page.loading}
            onClick={() => setCursors((list) => list.slice(0, -1))}
          >
            Previous
          </Button>
          <Button
            disabled={!page.data?.nextCursor || page.loading}
            onClick={() => setCursors((list) => [...list, page.data?.nextCursor ?? null])}
          >
            Next
          </Button>
        </div>
      </Card>
    </>
  );
}
