import { useCallback } from 'react';
import { Link } from 'react-router-dom';
import { isRouteNotDeployed } from '../api/errors';
import type { Commission, Payout } from '../api/types';
import { BalanceSummary } from '../components/BalanceSummary';
import { ErrorText } from '../components/ErrorText';
import { Loading } from '../components/Loading';
import { ComingSoonState, DataCard, EmptyState, PageHeader, StatusBadge } from '../components/ui';
import { useAsync } from '../components/useAsync';
import { usePaged } from '../components/usePaged';
import { moneyTone, pickLabel } from '../lib/labels';
import { formatBasisPoints, formatPaise } from '../lib/money';
import { usePortal } from '../state/PortalContext';

function LoadMore({
  list,
}: {
  list: { cursor: string | null; loading: boolean; loadMore: () => void };
}) {
  if (!list.cursor) return null;
  return (
    <button type="button" className="secondary" disabled={list.loading} onClick={list.loadMore}>
      {list.loading ? 'Loading…' : 'Load more'}
    </button>
  );
}

/** `GET /agent/balance` + `GET /agent/commissions`. Agents cannot request payouts. */
export function EarningsPage() {
  const { api, config } = usePortal();
  const balance = useAsync(useCallback(() => api.getBalance(), [api]));
  const list = usePaged<Commission>(
    useCallback((cursor) => api.getCommissions({ cursor }), [api]),
  );
  const historyMissing = isRouteNotDeployed(list.error);
  const bothMissing = historyMissing && isRouteNotDeployed(balance.error);

  return (
    <>
      <PageHeader
        title="Earnings"
        description="Payouts are made by the Nenjam team; you don't need to request one."
      />
      {bothMissing ? (
        <ComingSoonState title="Earnings coming soon" icon="coins">
          <p>Your balance will be available here soon.</p>
          <p>Your commissions list will be available here soon.</p>
        </ComingSoonState>
      ) : (
        <>
          <section aria-labelledby="bal-heading">
            <h2 id="bal-heading">Balance</h2>
            <BalanceSummary balance={balance} showMinimum />
          </section>
          <section aria-labelledby="hist-heading">
            <h2 id="hist-heading">Commission history</h2>
            {historyMissing ? (
              <ComingSoonState title="Commission history coming soon" icon="coins">
                Your commissions list will be available here soon.
              </ComingSoonState>
            ) : (
              <>
                {list.loading && list.items.length === 0 && <Loading />}
                <ErrorText error={list.error} onRetry={list.retry} />
                {!list.loading && !list.error && list.items.length === 0 && (
                  <EmptyState title="No commissions yet.">
                    You earn a commission when someone you referred buys their first paid plan.
                  </EmptyState>
                )}
                <ul className="list">
                  {list.items.map((c) => (
                    <DataCard
                      key={c.id}
                      title={formatPaise(c.amountPaise)}
                      badge={
                        <StatusBadge tone={moneyTone(c.status)}>
                          {pickLabel(config?.commissionStatusLabels[c.status], c.status)}
                        </StatusBadge>
                      }
                      facts={[
                        { label: 'Member', value: c.referralDisplayName },
                        { label: 'Plan', value: c.planName, wide: true },
                        {
                          label: 'Rate',
                          value: `${formatBasisPoints(c.rate.value)} of ${formatPaise(c.basePaise)}`,
                        },
                        { label: 'Earned', value: c.earnedOn },
                        ...(c.holdEndsOn ? [{ label: 'On hold until', value: c.holdEndsOn }] : []),
                        ...(c.paidOn ? [{ label: 'Paid', value: c.paidOn }] : []),
                      ]}
                    />
                  ))}
                </ul>
                <LoadMore list={list} />
              </>
            )}
          </section>
        </>
      )}
    </>
  );
}

/** `GET /agent/payouts` — read-only. `CREATED` is labelled from config ("Processing"). */
export function PayoutsPage() {
  const { api, agent, config } = usePortal();
  const list = usePaged<Payout>(useCallback((cursor) => api.getPayouts({ cursor }), [api]));
  const missing = isRouteNotDeployed(list.error);

  return (
    <>
      <PageHeader
        title="Payouts"
        description="Payouts are made by the Nenjam team to the details you saved."
        action={
          agent?.status === 'ACTIVE' ? (
            <Link to="/payout-details" className="button secondary">
              {agent.payoutDetailsSet ? 'Change payout details' : 'Add payout details'}
            </Link>
          ) : undefined
        }
      />
      {missing ? (
        <ComingSoonState title="Payouts coming soon" icon="wallet">
          Your payout history will be available here soon.
        </ComingSoonState>
      ) : (
        <>
          {list.loading && list.items.length === 0 && <Loading />}
          <ErrorText error={list.error} onRetry={list.retry} />
          {!list.loading && !list.error && list.items.length === 0 && (
            <EmptyState title="No payouts yet.">
              Paid-out commissions will be listed here with the date and reference.
            </EmptyState>
          )}
          <ul className="list">
            {list.items.map((p) => (
              <DataCard
                key={p.id}
                title={formatPaise(p.amountPaise)}
                badge={
                  <StatusBadge tone={moneyTone(p.status)}>
                    {pickLabel(config?.payoutStatusLabels[p.status], p.status)}
                  </StatusBadge>
                }
                facts={[
                  { label: 'Commissions', value: p.commissionCount },
                  { label: 'Created', value: p.createdOn },
                  ...(p.paidOn ? [{ label: 'Paid', value: p.paidOn }] : []),
                  ...(p.reference ? [{ label: 'Reference', value: p.reference, wide: true }] : []),
                ]}
              />
            ))}
          </ul>
          <LoadMore list={list} />
        </>
      )}
    </>
  );
}
