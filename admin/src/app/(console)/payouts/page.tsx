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
  Notice,
  PageHeader,
  useToast,
} from '@/components/ui';
import { formatDate, formatPaise } from '@/lib/format';
import { payoutReasonLabel, payoutStatusLabel, PERIOD_PATTERN, previousPeriod } from '@/lib/money';
import { can } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type { Page, PayableAgent, PayoutRow } from '@/lib/types';
import { useApi } from '@/lib/use-api';

/**
 * Paying agents: first who can be paid for a month, then the payouts made.
 * Creating a payout and marking it paid need a fresh authenticator code
 * (the panel asks for it) and the `payout.execute` permission.
 */
export default function PayoutsPage() {
  return (
    <RequirePermission permission="payout.view">
      <Payouts />
    </RequirePermission>
  );
}

function Payouts() {
  const { api, me } = useSession();
  const toast = useToast();
  const [period, setPeriod] = useState(() => previousPeriod(new Date()));
  const [periodInput, setPeriodInput] = useState(period);
  const [creating, setCreating] = useState<PayableAgent | null>(null);
  const [cursors, setCursors] = useState<Array<string | null>>([null]);
  const cursor = cursors[cursors.length - 1] ?? null;
  const canExecute = can(me?.permissions, 'payout.execute');
  const periodOk = PERIOD_PATTERN.test(period);

  const payable = useApi(
    (client) =>
      periodOk
        ? client.get<Page<PayableAgent>>('/admin/payouts/payable', { period, limit: 50 })
        : Promise.resolve({ items: [], nextCursor: null } as Page<PayableAgent>),
    [period],
  );
  const payouts = useApi(
    (client) => client.get<Page<PayoutRow>>('/admin/payouts', { cursor, limit: 25 }),
    [cursor],
  );

  return (
    <>
      <PageHeader
        title="Payouts"
        description="Pay agents their approved commission, one payout per agent per month."
      />

      <Card title="Who can be paid">
        <form
          className="filters"
          onSubmit={(event) => {
            event.preventDefault();
            if (PERIOD_PATTERN.test(periodInput)) setPeriod(periodInput);
          }}
        >
          <Field
            label="Month"
            hint="YYYY-MM, e.g. 2026-11. Normally last month."
            error={periodInput && !PERIOD_PATTERN.test(periodInput) ? 'Use YYYY-MM, e.g. 2026-11.' : null}
          >
            {(props) => (
              <input
                {...props}
                value={periodInput}
                maxLength={7}
                onChange={(e) => setPeriodInput(e.target.value.trim())}
              />
            )}
          </Field>
          <Button type="submit" tone="primary">
            Show
          </Button>
        </form>
        {payable.loading && !payable.data ? <Loading /> : null}
        {payable.error ? <ErrorState message={payable.error} onRetry={payable.reload} /> : null}
        {payable.data && payable.data.items.length === 0 ? (
          <EmptyState title="Nobody to pay for this month">
            Agents appear here once they have approved commission that is not paid yet.
          </EmptyState>
        ) : null}
        {payable.data && payable.data.items.length > 0 ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">Agent</th>
                  <th scope="col">To pay</th>
                  <th scope="col">PAN / payout details</th>
                  <th scope="col">Can be paid?</th>
                  <th scope="col">
                    <span className="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {payable.data.items.map((a) => (
                  <tr key={a.agentId}>
                    <td>
                      <Link href={`/agents/view/?id=${a.agentId}`}>{a.agentName}</Link>
                      <div className="muted small">{a.agentCode ?? '—'}</div>
                    </td>
                    <td>
                      {formatPaise(a.balancePaise)}
                      <div className="muted small">
                        {a.commissionCount} commission{a.commissionCount === 1 ? '' : 's'}
                      </div>
                    </td>
                    <td className="small">
                      PAN {a.panVerified ? 'verified' : 'not verified'}
                      <br />
                      {a.payoutDetails
                        ? `${a.payoutDetails.method} ${a.payoutDetails.display}${a.payoutDetails.verifiedAt ? '' : ' (not verified)'}`
                        : 'no payout details'}
                    </td>
                    <td className="small">
                      {a.eligible ? (
                        <Badge value="APPROVED" label="yes" />
                      ) : (
                        <ul className="plain">
                          {a.reasons.map((r) => (
                            <li key={r}>{payoutReasonLabel(r)}</li>
                          ))}
                        </ul>
                      )}
                    </td>
                    <td>
                      {a.eligible && canExecute ? (
                        <Button tone="primary" onClick={() => setCreating(a)}>
                          Create payout
                        </Button>
                      ) : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
        {payable.data?.items.some((a) => a.warnings.includes('TAX_RULE_NOT_SET')) ? (
          <Notice tone="warn">
            Tax withholding (TDS) isn&apos;t decided yet, so no tax is taken from these payouts.
          </Notice>
        ) : null}
      </Card>

      <Card title="Payouts">
        {payouts.loading && !payouts.data ? <Loading /> : null}
        {payouts.error ? <ErrorState message={payouts.error} onRetry={payouts.reload} /> : null}
        {payouts.data && payouts.data.items.length === 0 ? (
          <EmptyState title="No payouts yet" />
        ) : null}
        {payouts.data && payouts.data.items.length > 0 ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">Agent</th>
                  <th scope="col">Month</th>
                  <th scope="col">Amount</th>
                  <th scope="col">Status</th>
                  <th scope="col">Created</th>
                </tr>
              </thead>
              <tbody>
                {payouts.data.items.map((p) => (
                  <tr key={p.id}>
                    <td>
                      <Link href={`/payouts/view/?id=${p.id}`}>{p.agentName}</Link>
                      <div className="muted small">{p.agentCode ?? '—'}</div>
                    </td>
                    <td>{p.period}</td>
                    <td>{formatPaise(p.netPaise)}</td>
                    <td>
                      <Badge value={p.status} label={payoutStatusLabel(p.status)} />
                      {p.reference ? <div className="muted small">ref {p.reference}</div> : null}
                    </td>
                    <td>{formatDate(p.createdAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
        <div className="pager">
          <Button
            disabled={cursors.length <= 1 || payouts.loading}
            onClick={() => setCursors((list) => list.slice(0, -1))}
          >
            Previous
          </Button>
          <Button
            disabled={!payouts.data?.nextCursor || payouts.loading}
            onClick={() => setCursors((list) => [...list, payouts.data?.nextCursor ?? null])}
          >
            Next
          </Button>
        </div>
      </Card>

      <ConfirmDialog
        open={creating !== null}
        title={`Create a payout for ${creating?.agentName ?? ''}?`}
        confirmLabel="Create payout"
        requireReason
        onClose={() => setCreating(null)}
        onConfirm={async (reason) => {
          if (!creating) return;
          await api.post('/admin/payouts', {
            agentId: creating.agentId,
            period: creating.period,
            reason,
          });
          payable.reload();
          payouts.reload();
          toast('success', 'Payout created. Pay it, then mark it paid with the transfer reference.');
        }}
      >
        {creating ? (
          <p>
            {formatPaise(creating.balancePaise)} for {creating.period}. It locks these commissions
            to this payout; you then pay the agent outside the panel (UPI or bank) and record the
            reference. If one already exists for this month, that payout is returned and nothing
            changes.
          </p>
        ) : null}
      </ConfirmDialog>
    </>
  );
}
