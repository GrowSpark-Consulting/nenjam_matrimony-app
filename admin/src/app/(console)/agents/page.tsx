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
import { AGENT_STATUSES, agentStatusLabel } from '@/lib/agents';
import { formatDate } from '@/lib/format';
import type { AgentRow, AgentsSummary, Page } from '@/lib/types';
import { useApi } from '@/lib/use-api';

interface Filters {
  q: string;
  status: string;
}

/**
 * Partner Program agents: applications awaiting approval first, then
 * everyone else. Phones are masked by the API; opening an agent shows its
 * codes, payout details (masked) and history, and lets a Partner Manager
 * approve or reject an application.
 */
export default function AgentsPage() {
  return (
    <RequirePermission permission="agent.view">
      <Agents />
    </RequirePermission>
  );
}

function Agents() {
  const [draft, setDraft] = useState<Filters>({ q: '', status: 'PENDING_APPROVAL' });
  const [filters, setFilters] = useState<Filters>(draft);
  const [cursors, setCursors] = useState<Array<string | null>>([null]);
  const cursor = cursors[cursors.length - 1] ?? null;

  const summary = useApi((api) => api.get<AgentsSummary>('/admin/agents/summary'), []);
  const page = useApi(
    (api) =>
      api.get<Page<AgentRow>>('/admin/agents', {
        q: filters.q || undefined,
        status: filters.status || undefined,
        cursor,
        limit: 25,
      }),
    [filters, cursor],
  );

  const showStatus = (status: string) => {
    const next = { ...draft, status };
    setDraft(next);
    setCursors([null]);
    setFilters(next);
  };

  return (
    <>
      <PageHeader
        title="Agents"
        description="Partner Program applications and agents. Phone numbers are masked."
      />

      <Card title="Overview">
        {summary.loading && !summary.data ? <Loading /> : null}
        {summary.error ? <ErrorState message={summary.error} onRetry={summary.reload} /> : null}
        {summary.data ? (
          <>
            <div className="status-tiles">
              {AGENT_STATUSES.map((status) => (
                <button
                  key={status}
                  type="button"
                  className={`status-tile ${filters.status === status ? 'status-tile-selected' : ''}`}
                  aria-pressed={filters.status === status}
                  onClick={() => showStatus(status)}
                >
                  <span className="status-tile-value">{summary.data?.byStatus[status] ?? 0}</span>
                  <span className="status-tile-label">{agentStatusLabel(status)}</span>
                </button>
              ))}
            </div>
            <p className="muted small">
              Payout details awaiting verification:{' '}
              {summary.data.payoutDetailsAwaitingVerification} · Referrals needing review:{' '}
              {summary.data.referralsNeedingReview}
            </p>
          </>
        ) : null}
      </Card>

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
            label="Agent"
            hint="Agent id, referral code (NM…), full phone (+91…) or the start of a name."
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
                {AGENT_STATUSES.map((status) => (
                  <option key={status} value={status}>
                    {agentStatusLabel(status)}
                  </option>
                ))}
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
          <EmptyState title="No agents found">
            {filters.status === 'PENDING_APPROVAL' && !filters.q
              ? 'No applications are waiting for approval.'
              : null}
          </EmptyState>
        ) : null}
        {page.data && page.data.items.length > 0 ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">Agent</th>
                  <th scope="col">Place</th>
                  <th scope="col">Status</th>
                  <th scope="col">Code</th>
                  <th scope="col">Applied</th>
                  <th scope="col">PAN / payout</th>
                </tr>
              </thead>
              <tbody>
                {page.data.items.map((agent) => (
                  <tr key={agent.id}>
                    <td>
                      <Link href={`/agents/view/?id=${agent.id}`}>{agent.name}</Link>
                      <div className="muted small">{agent.phoneMasked}</div>
                    </td>
                    <td>
                      {agent.city}, {agent.state}
                    </td>
                    <td>
                      <Badge value={agent.status} label={agentStatusLabel(agent.status)} />
                    </td>
                    <td>{agent.primaryCode ? <code>{agent.primaryCode}</code> : '—'}</td>
                    <td>{formatDate(agent.createdAt)}</td>
                    <td className="small">
                      PAN {agent.panOnFile ? (agent.panVerified ? 'verified' : 'on file') : '—'}
                      <br />
                      Payout{' '}
                      {agent.payoutDetailsSet
                        ? agent.payoutDetailsVerified
                          ? 'verified'
                          : 'set, not verified'
                        : '—'}
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
