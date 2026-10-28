'use client';

import { useState } from 'react';
import { RequirePermission } from '@/components/AppShell';
import {
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  Loading,
  PageHeader,
} from '@/components/ui';
import { formatDateTime } from '@/lib/format';
import type { AuditRow, Page } from '@/lib/types';
import { useApi } from '@/lib/use-api';

interface Filters {
  action: string;
  entity: string;
  entityId: string;
  actorId: string;
  from: string;
  to: string;
}

const EMPTY: Filters = { action: '', entity: '', entityId: '', actorId: '', from: '', to: '' };

/** Read-only by design: there is no route that edits or deletes audit rows. */
export default function AuditPage() {
  return (
    <RequirePermission permission="audit.view">
      <Audit />
    </RequirePermission>
  );
}

function Audit() {
  const [draft, setDraft] = useState<Filters>(EMPTY);
  const [filters, setFilters] = useState<Filters>(EMPTY);
  const [cursors, setCursors] = useState<Array<string | null>>([null]);
  const cursor = cursors[cursors.length - 1] ?? null;

  const page = useApi(
    (api) =>
      api.get<Page<AuditRow>>('/admin/audit-logs', {
        action: filters.action,
        entity: filters.entity,
        entityId: filters.entityId,
        actorId: filters.actorId,
        // Dates are typed in local (IST) time; the API takes ISO instants.
        from: filters.from ? new Date(`${filters.from}T00:00:00`).toISOString() : undefined,
        to: filters.to ? new Date(`${filters.to}T23:59:59`).toISOString() : undefined,
        cursor,
        limit: 50,
      }),
    [filters, cursor],
  );

  const input = (key: keyof Filters, type = 'text') =>
    function Input(props: { id: string }) {
      return (
        <input
          {...props}
          type={type}
          value={draft[key]}
          onChange={(e) => setDraft({ ...draft, [key]: e.target.value })}
        />
      );
    };

  return (
    <>
      <PageHeader
        title="Audit log"
        description="Every sensitive admin action and refused access, newest first. Read-only."
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
          <Field label="Action starts with" hint="e.g. membership.plan or admin.access">
            {input('action')}
          </Field>
          <Field label="Entity">{input('entity')}</Field>
          <Field label="Entity id">{input('entityId')}</Field>
          <Field label="Actor id">{input('actorId')}</Field>
          <Field label="From">{input('from', 'date')}</Field>
          <Field label="To">{input('to', 'date')}</Field>
          <div className="row-actions">
            <Button type="submit" tone="primary">
              Filter
            </Button>
            <Button
              onClick={() => {
                setDraft(EMPTY);
                setCursors([null]);
                setFilters(EMPTY);
              }}
            >
              Clear
            </Button>
          </div>
        </form>
      </Card>

      <Card>
        {page.loading && !page.data ? <Loading /> : null}
        {page.error ? <ErrorState message={page.error} onRetry={page.reload} /> : null}
        {page.data && page.data.items.length === 0 ? (
          <EmptyState title="No matching entries" />
        ) : null}
        {page.data && page.data.items.length > 0 ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">When</th>
                  <th scope="col">Who</th>
                  <th scope="col">Action</th>
                  <th scope="col">On</th>
                  <th scope="col">Reason</th>
                  <th scope="col">Details</th>
                </tr>
              </thead>
              <tbody>
                {page.data.items.map((row) => (
                  <tr key={row.id}>
                    <td className="nowrap">{formatDateTime(row.createdAt)}</td>
                    <td>{row.actor ?? <code>{row.actorId?.slice(0, 8)}</code>}</td>
                    <td>
                      <code>{row.action}</code>
                    </td>
                    <td>
                      {row.entity}
                      {row.entityId ? (
                        <div className="muted small">
                          <code>{row.entityId}</code>
                        </div>
                      ) : null}
                    </td>
                    <td>{row.reason ?? '—'}</td>
                    <td>
                      {row.before || row.after || row.metadata ? (
                        <details>
                          <summary>View</summary>
                          <pre className="json">
                            {JSON.stringify(
                              { before: row.before, after: row.after, metadata: row.metadata, requestId: row.requestId },
                              null,
                              2,
                            )}
                          </pre>
                        </details>
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
            Newer
          </Button>
          <Button
            disabled={!page.data?.nextCursor || page.loading}
            onClick={() => setCursors((list) => [...list, page.data?.nextCursor ?? null])}
          >
            Older
          </Button>
        </div>
      </Card>
    </>
  );
}
