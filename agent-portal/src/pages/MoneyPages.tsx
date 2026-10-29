import { useCallback } from 'react';
import type { Commission, Payout } from '../api/types';
import { ErrorText } from '../components/ErrorText';
import { Loading } from '../components/Loading';
import { useAsync } from '../components/useAsync';
import { usePaged } from '../components/usePaged';
import { pickLabel } from '../lib/labels';
import { formatBasisPoints, formatPaise } from '../lib/money';
import { usePortal } from '../state/PortalContext';

/** `GET /agent/balance` + `GET /agent/commissions`. Agents cannot request payouts. */
export function EarningsPage() {
  const { api, config } = usePortal();
  const balance = useAsync(useCallback(() => api.getBalance(), [api]));
  const list = usePaged<Commission>(
    useCallback((cursor) => api.getCommissions({ cursor }), [api]),
  );
  return (
    <section>
      <h1>Earnings</h1>
      {balance.loading && <Loading />}
      <ErrorText error={balance.error} onRetry={balance.reload} />
      {balance.data && (
        <dl className="facts">
          <dt>On hold</dt>
          <dd>{formatPaise(balance.data.onHoldPaise)}</dd>
          <dt>Available</dt>
          <dd>{formatPaise(balance.data.availablePaise)}</dd>
          <dt>Paid</dt>
          <dd>{formatPaise(balance.data.paidPaise)}</dd>
          <dt>Minimum payout</dt>
          <dd>{formatPaise(balance.data.minPayoutPaise)}</dd>
        </dl>
      )}
      <p className="hint">Payouts are made by the Nenjam team; you don't need to request one.</p>
      {list.loading && list.items.length === 0 && <Loading />}
      <ErrorText error={list.error} onRetry={list.retry} />
      {!list.loading && !list.error && list.items.length === 0 && <p>No commissions yet.</p>}
      <ul className="list">
        {list.items.map((c) => (
          <li key={c.id} className="card">
            <strong>{formatPaise(c.amountPaise)}</strong> ·{' '}
            {pickLabel(config?.commissionStatusLabels[c.status], c.status)}
            <br />
            {c.referralDisplayName} · {c.planName} · {formatBasisPoints(c.rate.value)} of{' '}
            {formatPaise(c.basePaise)}
            <br />
            Earned {c.earnedOn}
            {c.holdEndsOn && ` · on hold until ${c.holdEndsOn}`}
            {c.paidOn && ` · paid ${c.paidOn}`}
          </li>
        ))}
      </ul>
      {list.cursor && (
        <button disabled={list.loading} onClick={list.loadMore}>
          Load more
        </button>
      )}
    </section>
  );
}

/** `GET /agent/payouts` — read-only. `CREATED` is labelled from config ("Processing"). */
export function PayoutsPage() {
  const { api, config } = usePortal();
  const list = usePaged<Payout>(useCallback((cursor) => api.getPayouts({ cursor }), [api]));
  return (
    <section>
      <h1>Payouts</h1>
      {list.loading && list.items.length === 0 && <Loading />}
      <ErrorText error={list.error} onRetry={list.retry} />
      {!list.loading && !list.error && list.items.length === 0 && <p>No payouts yet.</p>}
      <ul className="list">
        {list.items.map((p) => (
          <li key={p.id} className="card">
            <strong>{formatPaise(p.amountPaise)}</strong> ·{' '}
            {pickLabel(config?.payoutStatusLabels[p.status], p.status)}
            <br />
            {p.commissionCount} commissions · created {p.createdOn}
            {p.paidOn && ` · paid ${p.paidOn}`}
            {p.reference && ` · ref ${p.reference}`}
          </li>
        ))}
      </ul>
      {list.cursor && (
        <button disabled={list.loading} onClick={list.loadMore}>
          Load more
        </button>
      )}
    </section>
  );
}
