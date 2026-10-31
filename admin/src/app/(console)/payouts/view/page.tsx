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
  Field,
  Loading,
  Notice,
  PageHeader,
  useToast,
} from '@/components/ui';
import { formatDate, formatDateTime, formatPaise } from '@/lib/format';
import { commissionStatusLabel, formatBps, payoutStatusLabel } from '@/lib/money';
import { can } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type { PayoutDetail } from '@/lib/types';
import { useApi } from '@/lib/use-api';

export default function PayoutViewPage() {
  return (
    <RequirePermission permission="payout.view">
      <Suspense fallback={<Loading />}>
        <PayoutView />
      </Suspense>
    </RequirePermission>
  );
}

/** `datetime-local` text (local time) → an ISO timestamp, or null. */
function toIso(local: string): string | null {
  if (!local) return null;
  const date = new Date(local);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function PayoutView() {
  const id = useSearchParams().get('id') ?? '';
  const { api, me } = useSession();
  const toast = useToast();
  const payout = useApi((client) => client.get<PayoutDetail>(`/admin/payouts/${id}`), [id]);
  const [action, setAction] = useState<'paid' | 'cancel' | null>(null);
  const [reference, setReference] = useState('');
  const [paidAt, setPaidAt] = useState('');

  if (!id) return <ErrorState message="No payout id in the address." />;
  if (payout.loading && !payout.data) return <Loading />;
  if (payout.error) return <ErrorState message={payout.error} onRetry={payout.reload} />;
  const p = payout.data;
  if (!p) return null;

  const canExecute = can(me?.permissions, 'payout.execute');
  const open = p.status === 'CREATED';
  const paidAtIso = toIso(paidAt);
  const markProblem = !reference.trim()
    ? 'Enter the bank or UPI transfer reference.'
    : !paidAtIso
      ? 'Enter when it was paid.'
      : new Date(paidAtIso).getTime() > Date.now() + 60_000
        ? "The payment time can't be in the future."
        : null;
  const dest = p.destination;

  return (
    <>
      <PageHeader
        title={`Payout for ${p.agentName}`}
        description={
          <>
            <Badge value={p.status} label={payoutStatusLabel(p.status)} /> · {p.period} ·{' '}
            {formatPaise(p.netPaise)}
          </>
        }
        actions={
          <div className="row-actions">
            <Link href="/payouts/">Back</Link>
            {open && canExecute ? (
              <>
                <Button
                  tone="primary"
                  onClick={() => {
                    setReference('');
                    setPaidAt('');
                    setAction('paid');
                  }}
                >
                  Mark as paid
                </Button>
                <Button tone="danger" onClick={() => setAction('cancel')}>
                  Cancel payout
                </Button>
              </>
            ) : null}
          </div>
        }
      />

      {p.status === 'CANCELLED' && p.cancelReason ? (
        <Notice tone="warn">Cancelled: {p.cancelReason}</Notice>
      ) : null}
      {p.warnings.includes('TAX_RULE_NOT_SET') ? (
        <Notice tone="warn">Tax withholding (TDS) isn&apos;t decided yet, so none was taken.</Notice>
      ) : null}

      <div className="grid">
        <Card title="Payout">
          <ul className="kv">
            <li>
              <span>Agent</span>
              <span>
                <Link href={`/agents/view/?id=${p.agentId}`}>{p.agentName}</Link>{' '}
                <code>{p.agentCode ?? ''}</code>
              </span>
            </li>
            <li>
              <span>Amount</span>
              <span>{formatPaise(p.amountPaise)}</span>
            </li>
            <li>
              <span>Tax withheld</span>
              <span>{formatPaise(p.taxWithheldPaise)}</span>
            </li>
            <li>
              <span>To pay</span>
              <strong>{formatPaise(p.netPaise)}</strong>
            </li>
            <li>
              <span>Created</span>
              <span>{formatDateTime(p.createdAt)}</span>
            </li>
            {p.paidAt ? (
              <li>
                <span>Paid</span>
                <span>
                  {formatDateTime(p.paidAt)} · ref <code>{p.reference}</code>
                </span>
              </li>
            ) : null}
          </ul>
        </Card>

        <Card title="Pay to">
          {dest ? (
            <ul className="kv">
              {dest.upi ? (
                <li>
                  <span>UPI</span>
                  <code>{dest.upi.vpa}</code>
                </li>
              ) : null}
              {dest.bank ? (
                <>
                  <li>
                    <span>Account holder</span>
                    <span>{dest.bank.accountHolderName}</span>
                  </li>
                  <li>
                    <span>Account number</span>
                    <code>{dest.bank.accountNumber}</code>
                  </li>
                  <li>
                    <span>IFSC</span>
                    <code>{dest.bank.ifsc}</code>
                  </li>
                </>
              ) : null}
            </ul>
          ) : (
            <p className="muted">
              {open && canExecute
                ? 'The payment details show after a recent authenticator check. Click “Mark as paid” (you will be asked for a code), or reload this page after entering a code.'
                : 'The payment details are not shown to you.'}
            </p>
          )}
          <p className="muted small">Shown only to the person who pays, and every view is recorded.</p>
        </Card>
      </div>

      <Card title="Commissions in this payout">
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Plan</th>
                <th scope="col">Member paid</th>
                <th scope="col">Commission</th>
                <th scope="col">Status</th>
                <th scope="col">Earned</th>
              </tr>
            </thead>
            <tbody>
              {p.commissions.map((c) => (
                <tr key={c.id}>
                  <td>{c.planName}</td>
                  <td>{formatPaise(c.paidPaise)}</td>
                  <td>
                    {c.amountPaise === null ? '—' : formatPaise(c.amountPaise)}{' '}
                    <span className="muted small">({formatBps(c.rate.value)})</span>
                  </td>
                  <td>
                    <Badge value={c.status} label={commissionStatusLabel(c.status)} />
                  </td>
                  <td>{formatDate(c.earnedOn)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      <ConfirmDialog
        open={action === 'paid'}
        title="Mark this payout as paid"
        confirmLabel="Mark as paid"
        requireReason
        reasonLabel="Note (kept in the audit log)"
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          if (markProblem || !paidAtIso) throw new Error(markProblem ?? 'Enter when it was paid.');
          payout.setData(
            await api.post<PayoutDetail>(`/admin/payouts/${p.id}/mark-paid`, {
              reference: reference.trim(),
              paidAt: paidAtIso,
              reason,
            }),
          );
          toast('success', 'Payout marked as paid.');
        }}
      >
        <p>
          Do this <strong>after</strong> you have sent {formatPaise(p.netPaise)} to the agent. It
          records the transfer and can&apos;t be undone.
        </p>
        <Field label="Transfer reference" hint="The UPI or bank transaction reference.">
          {(props) => (
            <input
              {...props}
              value={reference}
              maxLength={100}
              onChange={(e) => setReference(e.target.value)}
            />
          )}
        </Field>
        <Field label="Paid at" hint="Date and time of the transfer.">
          {(props) => (
            <input
              {...props}
              type="datetime-local"
              value={paidAt}
              onChange={(e) => setPaidAt(e.target.value)}
            />
          )}
        </Field>
      </ConfirmDialog>

      <ConfirmDialog
        open={action === 'cancel'}
        title="Cancel this payout?"
        confirmLabel="Cancel payout"
        tone="danger"
        requireReason
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          payout.setData(
            await api.post<PayoutDetail>(`/admin/payouts/${p.id}/cancel`, { reason }),
          );
          toast('success', 'Payout cancelled. The commissions can be paid again.');
        }}
      >
        <p>
          Nothing has been paid. The commissions go back to approved, and a new payout can be
          created for this month.
        </p>
      </ConfirmDialog>
    </>
  );
}
