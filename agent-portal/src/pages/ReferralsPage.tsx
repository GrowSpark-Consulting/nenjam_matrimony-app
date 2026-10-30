import { useCallback, useState } from 'react';
import type { ReferralStage, ReferralView } from '../api/types';
import { ErrorText } from '../components/ErrorText';
import { Loading } from '../components/Loading';
import { DataCard, EmptyState, PageHeader, StatusBadge } from '../components/ui';
import { usePaged } from '../components/usePaged';
import { moneyTone, pickLabel } from '../lib/labels';
import { usePortal } from '../state/PortalContext';

const STAGES: ReferralStage[] = ['REGISTERED', 'PROFILE_COMPLETE', 'PURCHASED'];

/**
 * `GET /agent/referrals` — cursor paging and an optional stage filter. Shows
 * ONLY the fields the contract allows (privacy rule); labels from config.
 */
export function ReferralsPage() {
  const { api, config } = usePortal();
  const [stage, setStage] = useState<ReferralStage | ''>('');
  const list = usePaged<ReferralView>(
    useCallback(
      (cursor: string | null) => api.getReferrals({ cursor, stage: stage || undefined }),
      [api, stage],
    ),
  );
  const { items, cursor, error, loading } = list;

  return (
    <>
      <PageHeader
        title="People who joined"
        description="Everyone who signed up with your code. For privacy, you only see limited details."
      />
      <div className="toolbar">
        <label htmlFor="stage">Stage</label>
        <select id="stage" value={stage} onChange={(e) => setStage(e.target.value as ReferralStage | '')}>
          <option value="">All</option>
          {STAGES.map((s) => (
            <option key={s} value={s}>
              {pickLabel(config?.stageLabels[s], s)}
            </option>
          ))}
        </select>
      </div>
      {loading && items.length === 0 && <Loading />}
      <ErrorText error={error} onRetry={list.retry} />
      {!loading && !error && items.length === 0 && (
        <EmptyState title="No one has joined with your code yet.">
          Share your referral code from Home to get started.
        </EmptyState>
      )}
      <ul className="list">
        {items.map((r) => (
          <DataCard
            key={r.id}
            title={`${r.displayName}, ${r.age}`}
            badge={
              <StatusBadge tone={moneyTone(r.stage)}>
                {pickLabel(config?.stageLabels[r.stage], r.stage)}
              </StatusBadge>
            }
            facts={[
              { label: 'City', value: r.city },
              { label: 'Profile', value: `${r.profileCompletenessPct}% complete` },
              { label: 'Joined', value: r.signedUpAt },
              { label: 'Phone', value: r.maskedPhone },
              ...(r.planName
                ? [{ label: 'Plan', value: `${r.planName}${r.purchasedAt ? ` · ${r.purchasedAt}` : ''}`, wide: true }]
                : []),
              ...(r.commissionStatus
                ? [
                    {
                      label: 'Commission',
                      value: pickLabel(
                        config?.commissionStatusLabels[r.commissionStatus],
                        r.commissionStatus,
                      ),
                    },
                  ]
                : []),
            ]}
          />
        ))}
      </ul>
      {cursor && (
        <button type="button" className="secondary" disabled={loading} onClick={list.loadMore}>
          {loading ? 'Loading…' : 'Load more'}
        </button>
      )}
    </>
  );
}
