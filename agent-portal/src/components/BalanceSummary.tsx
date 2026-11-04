import { isRouteNotDeployed } from '../api/errors';
import type { Balance } from '../api/types';
import { formatPaise } from '../lib/money';
import { ErrorText } from './ErrorText';
import { Loading } from './Loading';
import { ComingSoonState, SummaryCard } from './ui';
import type { AsyncState } from './useAsync';

/**
 * Balance figures from `GET /agent/balance`. While that route isn't deployed
 * it shows a "coming soon" note, never zeros; any other failure is a real,
 * retryable error.
 */
export function BalanceSummary({
  balance,
  showMinimum = false,
}: {
  balance: AsyncState<Balance>;
  showMinimum?: boolean;
}) {
  if (balance.loading) return <Loading label="Loading your balance…" />;
  if (isRouteNotDeployed(balance.error)) {
    return (
      <ComingSoonState title="Balance coming soon" icon="wallet">
        Your balance will be available here soon.
      </ComingSoonState>
    );
  }
  if (balance.error) return <ErrorText error={balance.error} onRetry={balance.reload} />;
  if (!balance.data) return null;
  const b = balance.data;
  return (
    <div className="summary-grid">
      <SummaryCard label="On hold" value={formatPaise(b.onHoldPaise)} hint="Waiting out the hold period" />
      <SummaryCard label="Available" value={formatPaise(b.availablePaise)} hint="Ready for the next payout" />
      <SummaryCard label="Paid" value={formatPaise(b.paidPaise)} hint="Already paid to you" />
      {showMinimum && <SummaryCard label="Minimum payout" value={formatPaise(b.minPayoutPaise)} />}
    </div>
  );
}
