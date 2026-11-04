'use client';

import Link from 'next/link';
import { useState } from 'react';
import { RequirePermission } from '@/components/AppShell';
import {
  Badge,
  Button,
  Card,
  ConfirmDialog,
  EmptyState,
  ErrorState,
  Field,
  Loading,
  PageHeader,
  useToast,
} from '@/components/ui';
import { formatDate, formatPaise, paiseToRupeesInput, rupeesToPaise } from '@/lib/format';
import { agentStatusLabel } from '@/lib/agents';
import { COMMISSION_STATUSES, commissionActions, commissionStatusLabel, formatBps } from '@/lib/money';
import { can } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type { CommissionRow, Page } from '@/lib/types';
import { useApi } from '@/lib/use-api';

/**
 * Agent commissions, newest first. Approving, cancelling and overriding an
 * amount need a reason; the API audits each in the same transaction.
 */
export default function CommissionsPage() {
  return (
    <RequirePermission permission="commission.view">
      <Commissions />
    </RequirePermission>
  );
}

type Action = 'approve' | 'cancel' | 'override';

function Commissions() {
  const { api, me } = useSession();
  const toast = useToast();
  const [status, setStatus] = useState('');
  const [cursors, setCursors] = useState<Array<string | null>>([null]);
  const cursor = cursors[cursors.length - 1] ?? null;
  const [target, setTarget] = useState<{ row: CommissionRow; action: Action } | null>(null);
  const [amount, setAmount] = useState('');

  const page = useApi(
    (client) =>
      client.get<Page<CommissionRow>>('/admin/commissions', {
        status: status || undefined,
        cursor,
        limit: 25,
      }),
    [status, cursor],
  );

  const open = (row: CommissionRow, action: Action) => {
    setAmount(action === 'override' ? paiseToRupeesInput(row.amountPaise) : '');
    setTarget({ row, action });
  };
  const decide = async (action: 'approve' | 'cancel', row: CommissionRow, reason: string) => {
    await api.post(`/admin/commissions/${row.id}/${action}`, { reason });
    page.reload();
  };

  const row = target?.row;
  // The API allows 0 (no commission); rupeesToPaise only reads positive amounts.
  const overridePaise = /^0+(\.0{1,2})?$/.test(amount.trim()) ? 0 : rupeesToPaise(amount);
  const overrideProblem =
    overridePaise === null || Number.isNaN(overridePaise)
      ? 'Enter the commission in rupees, e.g. 99.90.'
      : row && overridePaise > row.paidPaise
        ? `It can't be more than what the member paid (${formatPaise(row.paidPaise)}).`
        : null;

  return (
    <>
      <PageHeader
        title="Commissions"
        description="What agents earned from their members’ first plans. Amounts are on the price without GST."
      />
      <Card>
        <div className="filters">
          <Field label="Status">
            {(props) => (
              <select
                {...props}
                value={status}
                onChange={(e) => {
                  setStatus(e.target.value);
                  setCursors([null]);
                }}
              >
                <option value="">Any</option>
                {COMMISSION_STATUSES.map((s) => (
                  <option key={s} value={s}>
                    {commissionStatusLabel(s)}
                  </option>
                ))}
              </select>
            )}
          </Field>
        </div>
      </Card>

      <Card>
        {page.loading && !page.data ? <Loading /> : null}
        {page.error ? <ErrorState message={page.error} onRetry={page.reload} /> : null}
        {page.data && page.data.items.length === 0 ? (
          <EmptyState title="No commissions">
            A commission appears when a referred member pays for their first plan with real money.
          </EmptyState>
        ) : null}
        {page.data && page.data.items.length > 0 ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">Agent</th>
                  <th scope="col">Plan</th>
                  <th scope="col">Member paid</th>
                  <th scope="col">Commission</th>
                  <th scope="col">Status</th>
                  <th scope="col">Dates</th>
                  <th scope="col">
                    <span className="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {page.data.items.map((c) => {
                  const actions = commissionActions(c.status);
                  return (
                    <tr key={c.id}>
                      <td>
                        <Link href={`/agents/view/?id=${c.agentId}`}>{c.agentName}</Link>
                        {c.agentStatus !== 'ACTIVE' ? (
                          <div className="muted small">agent {agentStatusLabel(c.agentStatus)}</div>
                        ) : null}
                      </td>
                      <td>{c.planName}</td>
                      <td>{formatPaise(c.paidPaise)}</td>
                      <td>
                        {c.amountPaise === null ? (
                          <span className="muted">not set</span>
                        ) : (
                          formatPaise(c.amountPaise)
                        )}
                        <div className="muted small">
                          {formatBps(c.rate.value)}
                          {c.reversedPaise > 0 ? ` · refunded ${formatPaise(c.reversedPaise)}` : ''}
                        </div>
                      </td>
                      <td>
                        <Badge value={c.status} label={commissionStatusLabel(c.status)} />
                      </td>
                      <td className="small">
                        earned {formatDate(c.earnedOn)}
                        {c.holdEndsOn && c.status === 'ON_HOLD' ? (
                          <>
                            <br />
                            hold ends {formatDate(c.holdEndsOn)}
                          </>
                        ) : null}
                        {c.paidOn ? (
                          <>
                            <br />
                            paid {formatDate(c.paidOn)}
                          </>
                        ) : null}
                      </td>
                      <td>
                        <div className="row-actions">
                          {actions.includes('approve') && can(me?.permissions, 'commission.approve') ? (
                            <Button onClick={() => open(c, 'approve')}>Approve</Button>
                          ) : null}
                          {actions.includes('override') &&
                          can(me?.permissions, 'commission.override') ? (
                            <Button onClick={() => open(c, 'override')}>Set amount</Button>
                          ) : null}
                          {actions.includes('cancel') && can(me?.permissions, 'commission.cancel') ? (
                            <Button tone="danger" onClick={() => open(c, 'cancel')}>
                              Cancel
                            </Button>
                          ) : null}
                        </div>
                      </td>
                    </tr>
                  );
                })}
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

      <ConfirmDialog
        open={target?.action === 'approve'}
        title="Approve this commission?"
        confirmLabel="Approve"
        requireReason
        onClose={() => setTarget(null)}
        onConfirm={async (reason) => {
          if (!row) return;
          await decide('approve', row, reason);
          toast('success', 'Commission approved. It can now be included in a payout.');
        }}
      >
        {row ? (
          <p>
            {row.agentName}: {row.amountPaise === null ? 'amount not set yet' : formatPaise(row.amountPaise)}{' '}
            for a {row.planName} plan. Approval is refused while the amount is not set.
          </p>
        ) : null}
      </ConfirmDialog>

      <ConfirmDialog
        open={target?.action === 'cancel'}
        title="Cancel this commission?"
        confirmLabel="Cancel commission"
        tone="danger"
        requireReason
        onClose={() => setTarget(null)}
        onConfirm={async (reason) => {
          if (!row) return;
          await decide('cancel', row, reason);
          toast('success', 'Commission cancelled.');
        }}
      >
        <p>The agent will not be paid this commission. This can&apos;t be undone.</p>
      </ConfirmDialog>

      <ConfirmDialog
        open={target?.action === 'override'}
        title="Set the commission amount"
        confirmLabel="Set amount"
        requireReason
        onClose={() => setTarget(null)}
        onConfirm={async (reason) => {
          if (!row) return;
          if (overrideProblem || overridePaise === null) {
            throw new Error(overrideProblem ?? 'Enter an amount.');
          }
          await api.post(`/admin/commissions/${row.id}/override`, {
            amountPaise: overridePaise,
            reason,
          });
          page.reload();
          toast('success', 'Commission amount set.');
        }}
      >
        <Field
          label="Commission (₹)"
          hint="Replaces the calculated amount. It can't be more than what the member paid."
          error={amount && overrideProblem ? overrideProblem : null}
        >
          {(props) => (
            <input
              {...props}
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          )}
        </Field>
      </ConfirmDialog>
    </>
  );
}
