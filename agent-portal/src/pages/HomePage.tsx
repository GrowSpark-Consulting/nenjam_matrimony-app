import { useCallback } from 'react';
import { BalanceSummary } from '../components/BalanceSummary';
import { ErrorText } from '../components/ErrorText';
import { Loading } from '../components/Loading';
import { ReferralCodeCard } from '../components/ReferralCodeCard';
import { PageHeader, StatusBadge } from '../components/ui';
import { useAsync } from '../components/useAsync';
import { help } from '../lib/helpContent';
import { pickLabel, statusTone } from '../lib/labels';
import { usePortal } from '../state/PortalContext';

/**
 * Home: the agent's codes (`GET /agent/referral-links`) and a balance
 * summary (`GET /agent/balance`). The two load and fail independently, so
 * referral sharing keeps working when the money service is unavailable.
 */
export function HomePage() {
  const { api, agent, config } = usePortal();
  const links = useAsync(useCallback(() => api.getReferralLinks(), [api]));
  const balance = useAsync(useCallback(() => api.getBalance(), [api]));
  const firstName = agent?.name.trim().split(/\s+/)[0];

  return (
    <>
      <PageHeader
        title={firstName ? `Welcome, ${firstName}` : 'Welcome'}
        description={help.welcome}
        action={
          agent && (
            <StatusBadge tone={statusTone(agent.status)}>
              {pickLabel(config?.statusLabels[agent.status] ?? agent.statusLabel, agent.status)}
            </StatusBadge>
          )
        }
      />
      <section aria-labelledby="code-heading">
        <h2 id="code-heading">Your referral code</h2>
        {links.loading && <Loading />}
        <ErrorText error={links.error} onRetry={links.reload} />
        {links.data?.map((l) => <ReferralCodeCard key={l.codeId} link={l} />)}
      </section>
      <section aria-labelledby="balance-heading">
        <h2 id="balance-heading">Balance</h2>
        <BalanceSummary balance={balance} />
      </section>
    </>
  );
}
