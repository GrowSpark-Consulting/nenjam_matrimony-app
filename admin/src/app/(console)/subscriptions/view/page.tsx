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
  PageHeader,
  useToast,
} from '@/components/ui';
import { formatDate, formatDateTime, formatPaise, humanize } from '@/lib/format';
import { can } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type { SubscriptionDetail } from '@/lib/types';
import { useApi } from '@/lib/use-api';

export default function SubscriptionViewPage() {
  return (
    <RequirePermission permission="subscription.view">
      <Suspense fallback={<Loading />}>
        <SubscriptionView />
      </Suspense>
    </RequirePermission>
  );
}

function SubscriptionView() {
  const id = useSearchParams().get('id') ?? '';
  const { api, me } = useSession();
  const toast = useToast();
  const sub = useApi(
    (client) => client.get<SubscriptionDetail>(`/admin/subscriptions/${id}`),
    [id],
  );
  const [action, setAction] = useState<'extend' | 'revoke' | null>(null);
  const [days, setDays] = useState('7');

  if (!id) return <ErrorState message="No subscription id in the address." />;
  if (sub.loading && !sub.data) return <Loading />;
  if (sub.error) return <ErrorState message={sub.error} onRetry={sub.reload} />;
  const s = sub.data;
  if (!s) return null;

  const active = s.status === 'ACTIVE';
  const daysNumber = Number(days);
  const daysValid = Number.isInteger(daysNumber) && daysNumber >= 1 && daysNumber <= 30;

  return (
    <>
      <PageHeader
        title={`${s.plan.name} membership`}
        description={
          <>
            <Badge value={s.status} />{' '}
            {s.source === 'ADMIN_GRANT' ? 'Granted by an admin' : 'Purchased'} ·{' '}
            {formatDate(s.startDate)} – {formatDate(s.endDate)}
          </>
        }
        actions={
          <div className="row-actions">
            <Link href="/subscriptions/">Back</Link>
            {active && can(me?.permissions, 'subscription.extend') ? (
              <Button onClick={() => setAction('extend')}>Extend</Button>
            ) : null}
            {active && can(me?.permissions, 'subscription.cancel') ? (
              <Button tone="danger" onClick={() => setAction('revoke')}>
                Revoke
              </Button>
            ) : null}
          </div>
        }
      />

      <div className="grid">
        <Card title="Member">
          <ul className="kv">
            <li>
              <span>Name</span>
              <span>{s.member.name ?? '—'}</span>
            </li>
            <li>
              <span>Email</span>
              <span>{s.member.email ?? '—'}</span>
            </li>
            <li>
              <span>Phone</span>
              <span>{s.member.phone ?? '—'}</span>
            </li>
            <li>
              <span>User id</span>
              <code>{s.member.userId}</code>
            </li>
          </ul>
        </Card>
        <Card title="Plan">
          <ul className="kv">
            <li>
              <span>Plan</span>
              <span>
                {s.plan.name}
                {s.months ? ` · ${s.months} months` : ''}
              </span>
            </li>
            <li>
              <span>Entitlements version</span>
              <span>{s.planVersion ?? 'legacy'}</span>
            </li>
            <li>
              <span>Price paid</span>
              <span>{s.priceInPaise === null ? '—' : formatPaise(s.priceInPaise)}</span>
            </li>
            <li>
              <span>Activated</span>
              <span>{formatDateTime(s.activatedAt)}</span>
            </li>
            {s.cancelledAt ? (
              <li>
                <span>Cancelled</span>
                <span>
                  {formatDateTime(s.cancelledAt)} ({humanize(s.cancellationReason ?? '')})
                </span>
              </li>
            ) : null}
          </ul>
        </Card>
      </div>

      <Card title="Payments">
        {s.payments.length === 0 ? (
          <p className="muted">No payments.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">Created</th>
                  <th scope="col">Status</th>
                  <th scope="col">Amount</th>
                  <th scope="col">Refunded</th>
                  <th scope="col">Razorpay ids</th>
                </tr>
              </thead>
              <tbody>
                {s.payments.map((p) => (
                  <tr key={p.id}>
                    <td>{formatDateTime(p.createdAt)}</td>
                    <td>
                      <Badge value={p.status} />
                      {p.failureReason ? <div className="muted small">{p.failureReason}</div> : null}
                    </td>
                    <td>{formatPaise(p.amountInPaise)}</td>
                    <td>{p.refundedAmount ? formatPaise(p.refundedAmount) : '—'}</td>
                    <td className="small">
                      <code>{p.razorpayOrderId ?? '—'}</code>
                      <br />
                      <code>{p.razorpayPaymentId ?? '—'}</code>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card title="History">
        <ol className="timeline">
          {s.events.map((e) => (
            <li key={e.id}>
              <strong>{humanize(e.type)}</strong>{' '}
              <span className="muted">{formatDateTime(e.createdAt)}</span>
              {e.fromStatus || e.toStatus ? (
                <span className="muted small">
                  {' '}
                  · {e.fromStatus ?? '—'} → {e.toStatus ?? '—'}
                </span>
              ) : null}
              {e.metadata && typeof e.metadata === 'object' && 'reason' in e.metadata ? (
                <div>{String((e.metadata as { reason: unknown }).reason)}</div>
              ) : null}
            </li>
          ))}
        </ol>
      </Card>

      <ConfirmDialog
        open={action === 'extend'}
        title="Extend this membership"
        confirmLabel="Extend"
        requireReason
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          if (!daysValid) throw new Error('Enter 1 to 30 days.');
          sub.setData(
            await api.post<SubscriptionDetail>(`/admin/subscriptions/${s.id}/extend`, {
              days: daysNumber,
              reason,
            }),
          );
          toast('success', `Extended by ${daysNumber} days.`);
        }}
      >
        <Field
          label="Days to add"
          hint="Up to 30 days. Longer extensions need a second approver (not available yet)."
          error={days && !daysValid ? 'Enter 1 to 30 days.' : null}
        >
          {(props) => (
            <input
              {...props}
              inputMode="numeric"
              value={days}
              onChange={(e) => setDays(e.target.value.replace(/\D/g, ''))}
            />
          )}
        </Field>
      </ConfirmDialog>

      <ConfirmDialog
        open={action === 'revoke'}
        title="Revoke this membership?"
        confirmLabel="Revoke now"
        tone="danger"
        requireReason
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          sub.setData(
            await api.post<SubscriptionDetail>(`/admin/subscriptions/${s.id}/revoke`, { reason }),
          );
          toast('success', 'Membership revoked.');
        }}
      >
        <p>
          The member loses the plan immediately. Nothing is refunded — refunds go through the
          payment provider.
        </p>
      </ConfirmDialog>
    </>
  );
}
