import { useCallback, useState } from 'react';
import type { ReferralStage, ReferralView } from '../api/types';
import { ErrorText } from '../components/ErrorText';
import { Loading } from '../components/Loading';
import { usePaged } from '../components/usePaged';
import { pickLabel } from '../lib/labels';
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
    <section>
      <h1>People who joined</h1>
      <label htmlFor="stage">Stage</label>
      <select id="stage" value={stage} onChange={(e) => setStage(e.target.value as ReferralStage | '')}>
        <option value="">All</option>
        {STAGES.map((s) => (
          <option key={s} value={s}>
            {pickLabel(config?.stageLabels[s], s)}
          </option>
        ))}
      </select>
      {loading && items.length === 0 && <Loading />}
      <ErrorText error={error} onRetry={list.retry} />
      {!loading && !error && items.length === 0 && <p>No one has joined with your code yet.</p>}
      <ul className="list">
        {items.map((r) => (
          <li key={r.id} className="card">
            <strong>{r.displayName}</strong>, {r.age} · {r.city}
            <br />
            {pickLabel(config?.stageLabels[r.stage], r.stage)} · Profile {r.profileCompletenessPct}%
            <br />
            Joined {r.signedUpAt} · {r.maskedPhone}
            {r.planName && (
              <>
                <br />
                {r.planName}
                {r.purchasedAt && ` · ${r.purchasedAt}`}
              </>
            )}
            {r.commissionStatus && (
              <>
                <br />
                {pickLabel(config?.commissionStatusLabels[r.commissionStatus], r.commissionStatus)}
              </>
            )}
          </li>
        ))}
      </ul>
      {cursor && (
        <button disabled={loading} onClick={list.loadMore}>
          Load more
        </button>
      )}
    </section>
  );
}
