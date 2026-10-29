'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useMemo, useState, type ReactNode } from 'react';
import { RequirePermission } from '@/components/AppShell';
import {
  Badge,
  Button,
  Card,
  ConfirmDialog,
  ErrorState,
  Loading,
  Notice,
  PageHeader,
  useToast,
} from '@/components/ui';
import { bySection, describeValue, sameValue } from '@/lib/entitlements';
import {
  formatDateTime,
  formatPaise,
  humanize,
  paiseToRupeesInput,
  rupeesToPaise,
} from '@/lib/format';
import { can } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type {
  Duration,
  EntitlementValue,
  Entitlements,
  FeatureDescriptor,
  LimitValue,
  PlanDraft,
  PlansResponse,
} from '@/lib/types';
import { useApi } from '@/lib/use-api';

interface DurationRow {
  months: string;
  durationDays: string;
  bonusDays: string;
  price: string;
  isActive: boolean;
  isNew: boolean;
}

type Action = 'submit' | 'publish' | 'reject' | 'discard' | null;

export default function DraftPage() {
  return (
    <RequirePermission permission="plan.view">
      <Suspense fallback={<Loading />}>
        <DraftLoader />
      </Suspense>
    </RequirePermission>
  );
}

function DraftLoader() {
  const id = useSearchParams().get('id') ?? '';
  const draft = useApi((api) => api.get<PlanDraft>(`/admin/plan-drafts/${id}`), [id]);
  const catalogue = useApi((api) => api.get<PlansResponse>('/admin/plans'), [id]);

  if (!id) return <ErrorState message="No draft id in the address." />;
  if ((draft.loading && !draft.data) || (catalogue.loading && !catalogue.data)) {
    return <Loading />;
  }
  if (draft.error || catalogue.error) {
    return (
      <ErrorState
        message={draft.error ?? catalogue.error ?? 'Could not load the draft.'}
        onRetry={() => {
          void draft.reload();
          void catalogue.reload();
        }}
      />
    );
  }
  if (!draft.data || !catalogue.data) return null;
  return (
    <DraftEditor
      key={`${draft.data.id}-${draft.data.updatedAt}`}
      draft={draft.data}
      catalogue={catalogue.data}
      onChanged={(next) => draft.setData(next)}
      reloadCatalogue={catalogue.reload}
    />
  );
}

function toRows(durations: Duration[]): DurationRow[] {
  return durations.map((d) => ({
    months: String(d.months),
    durationDays: String(d.durationDays),
    bonusDays: String(d.bonusDays),
    price: paiseToRupeesInput(d.priceInPaise),
    isActive: d.isActive,
    isNew: false,
  }));
}

/** Rows → API durations, or the first problem a person should fix. */
function fromRows(rows: DurationRow[]): { durations: Duration[] } | { problem: string } {
  const durations: Duration[] = [];
  for (const row of rows) {
    const months = Number(row.months);
    const durationDays = Number(row.durationDays);
    const bonusDays = Number(row.bonusDays || '0');
    const label = row.months ? `${row.months} months` : 'A new length';
    if (!Number.isInteger(months) || months < 1 || months > 36) {
      return { problem: `${label}: length must be 1–36 months.` };
    }
    if (!Number.isInteger(durationDays) || durationDays < 1) {
      return { problem: `${label}: days must be a whole number.` };
    }
    if (!Number.isInteger(bonusDays) || bonusDays < 0) {
      return { problem: `${label}: bonus days must be 0 or more.` };
    }
    const priceInPaise = rupeesToPaise(row.price);
    if (Number.isNaN(priceInPaise)) {
      return { problem: `${label}: price must be an amount in rupees, e.g. 3999.` };
    }
    durations.push({ months, durationDays, bonusDays, priceInPaise, isActive: row.isActive });
  }
  return { durations };
}

function DraftEditor({
  draft,
  catalogue,
  onChanged,
  reloadCatalogue,
}: {
  draft: PlanDraft;
  catalogue: PlansResponse;
  onChanged: (draft: PlanDraft) => void;
  reloadCatalogue: () => Promise<void>;
}) {
  const { api, me } = useSession();
  const toast = useToast();
  const plan = catalogue.plans.find((p) => p.code === draft.planCode);
  const current = plan?.currentVersion?.entitlements ?? {};

  const [entitlements, setEntitlements] = useState<Entitlements>(draft.entitlements);
  const [rows, setRows] = useState<DurationRow[]>(toRows(draft.durations));
  const [changeNote, setChangeNote] = useState(draft.changeNote);
  const [saving, setSaving] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const [action, setAction] = useState<Action>(null);

  const editable = draft.status === 'DRAFT' && can(me?.permissions, 'plan.edit');
  const isSubmitter = draft.submittedById === me?.userId;
  const mayDecide =
    draft.status === 'SUBMITTED' && can(me?.permissions, 'plan.publish') && !isSubmitter;

  const dirty = useMemo(
    () =>
      !sameValue(entitlements, draft.entitlements) ||
      !sameValue(rows, toRows(draft.durations)) ||
      changeNote !== draft.changeNote,
    [entitlements, rows, changeNote, draft],
  );

  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => event.preventDefault();
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [dirty]);

  const who = (id: string | null) => (!id ? '—' : id === me?.userId ? 'you' : `admin ${id.slice(0, 8)}`);

  async function save() {
    const parsed = fromRows(rows);
    if ('problem' in parsed) {
      setProblem(parsed.problem);
      return;
    }
    setProblem(null);
    setSaving(true);
    try {
      const next = await api.put<PlanDraft>(`/admin/plan-drafts/${draft.id}`, {
        entitlements,
        durations: parsed.durations,
        changeNote,
      });
      toast('success', 'Draft saved.');
      onChanged(next);
    } catch (e) {
      setProblem(e instanceof Error ? e.message : 'Could not save the draft.');
    } finally {
      setSaving(false);
    }
  }

  const review = draft.review;
  const blockers = [...review.entitlementProblems, ...review.durationProblems];

  return (
    <>
      <PageHeader
        title={`${draft.planName}: ${draft.changeNote}`}
        description={
          <>
            <Badge value={draft.status} /> Started by {who(draft.createdById)} from version{' '}
            {draft.baseVersion ?? '—'} · current version {draft.currentVersion ?? '—'} · last
            saved {formatDateTime(draft.updatedAt)}
          </>
        }
        actions={<Link href="/plans/">Back to plans</Link>}
      />

      {draft.stale && (draft.status === 'DRAFT' || draft.status === 'SUBMITTED') ? (
        <Notice tone="warn">
          {draft.planName} was changed after this draft was started, so it can’t be published.
          Discard it and start a new draft.
        </Notice>
      ) : null}
      {draft.status === 'SUBMITTED' && isSubmitter ? (
        <Notice>
          You submitted this draft. A different admin with publish rights must approve it.
        </Notice>
      ) : null}
      {draft.decisionNote ? (
        <Notice tone={draft.status === 'REJECTED' ? 'error' : 'info'}>
          {draft.status === 'REJECTED' ? 'Rejected' : 'Approved'} by {who(draft.decidedById)} on{' '}
          {formatDateTime(draft.decidedAt)}: {draft.decisionNote}
        </Notice>
      ) : null}

      <div className="split">
        <div>
          {editable ? (
            <Card title="Change note">
              <label className="sr-only" htmlFor="change-note">
                Change note
              </label>
              <textarea
                id="change-note"
                rows={2}
                maxLength={500}
                value={changeNote}
                onChange={(e) => setChangeNote(e.target.value)}
              />
            </Card>
          ) : null}

          {!plan?.isFree ? (
            <Card
              title="Prices and lengths"
              actions={
                editable ? (
                  <Button
                    onClick={() =>
                      setRows((list) => [
                        ...list,
                        { months: '', durationDays: '', bonusDays: '0', price: '', isActive: false, isNew: true },
                      ])
                    }
                  >
                    Add a length
                  </Button>
                ) : null
              }
            >
              <p className="muted small">
                Prices in rupees, stored in paise. A length must be priced before it can be on
                sale. Existing lengths can be taken off sale but not removed.
              </p>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th scope="col">Months</th>
                      <th scope="col">Days</th>
                      <th scope="col">Bonus days</th>
                      <th scope="col">Price (₹)</th>
                      <th scope="col">On sale</th>
                      {editable ? <th scope="col"><span className="sr-only">Remove</span></th> : null}
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((row, index) => {
                      const set = (patch: Partial<DurationRow>) =>
                        setRows((list) => list.map((r, i) => (i === index ? { ...r, ...patch } : r)));
                      const label = `${row.months || 'new'} months`;
                      return (
                        <tr key={index}>
                          <td>
                            <input
                              aria-label={`Length in months (${label})`}
                              inputMode="numeric"
                              value={row.months}
                              disabled={!editable || !row.isNew}
                              onChange={(e) => set({ months: e.target.value })}
                            />
                          </td>
                          <td>
                            <input
                              aria-label={`Days (${label})`}
                              inputMode="numeric"
                              value={row.durationDays}
                              disabled={!editable}
                              onChange={(e) => set({ durationDays: e.target.value })}
                            />
                          </td>
                          <td>
                            <input
                              aria-label={`Bonus days (${label})`}
                              inputMode="numeric"
                              value={row.bonusDays}
                              disabled={!editable}
                              onChange={(e) => set({ bonusDays: e.target.value })}
                            />
                          </td>
                          <td>
                            <input
                              aria-label={`Price in rupees (${label})`}
                              inputMode="decimal"
                              placeholder="Not priced"
                              value={row.price}
                              disabled={!editable}
                              onChange={(e) => set({ price: e.target.value })}
                            />
                          </td>
                          <td>
                            <input
                              type="checkbox"
                              aria-label={`On sale (${label})`}
                              checked={row.isActive}
                              disabled={!editable}
                              onChange={(e) => set({ isActive: e.target.checked })}
                            />
                          </td>
                          {editable ? (
                            <td>
                              {row.isNew ? (
                                <Button
                                  tone="ghost"
                                  onClick={() => setRows((list) => list.filter((_, i) => i !== index))}
                                >
                                  Remove
                                </Button>
                              ) : null}
                            </td>
                          ) : null}
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </Card>
          ) : null}

          {bySection(catalogue.features).map(([section, features]) => (
            <Card key={section} title={humanize(section)}>
              {features.map((feature) => (
                <FeatureEditor
                  key={feature.key}
                  feature={feature}
                  value={entitlements[feature.key]}
                  current={current[feature.key]}
                  editable={editable}
                  onChange={(value) =>
                    setEntitlements((map) => ({ ...map, [feature.key]: value }))
                  }
                />
              ))}
            </Card>
          ))}
        </div>

        <aside className="sticky">
          <Card title="Review">
            {dirty ? <Notice tone="warn">Unsaved changes — save to update this review.</Notice> : null}
            {problem ? <Notice tone="error">{problem}</Notice> : null}
            {blockers.length > 0 ? (
              <>
                <strong>Fix before publishing</strong>
                <ul className="problems">
                  {blockers.map((p) => (
                    <li key={p}>{p}</li>
                  ))}
                </ul>
              </>
            ) : null}
            {!review.hasChanges ? <p className="muted">No changes from the current plan yet.</p> : null}
            {review.changedFeatures.length > 0 ? (
              <>
                <strong>Changed features</strong>
                <ul>
                  {review.changedFeatures.map((key) => (
                    <li key={key}>
                      {catalogue.features.find((f) => f.key === key)?.label ?? key}
                      {review.reductionsVsCurrent.includes(key) ? (
                        <Badge value="CANCELLED" label="less than now" />
                      ) : null}
                    </li>
                  ))}
                </ul>
              </>
            ) : null}
            {review.reductionsVsCurrent.length > 0 ? (
              <p className="muted small">
                Reductions apply to new purchases only. Members who already bought keep their
                version.
              </p>
            ) : null}
            {review.durationChanges.length > 0 ? (
              <>
                <strong>Price changes</strong>
                <ul>
                  {review.durationChanges.map((c) => (
                    <li key={c.months}>
                      {c.months} months: {c.before ? formatPaise(c.before.priceInPaise) : 'new'} →{' '}
                      {formatPaise(c.after.priceInPaise)}
                      {c.after.isActive ? ' (on sale)' : ' (off sale)'}
                    </li>
                  ))}
                </ul>
              </>
            ) : null}

            <div className="stack">
              {editable ? (
                <Button tone="primary" busy={saving} disabled={!dirty} onClick={() => void save()}>
                  Save draft
                </Button>
              ) : null}
              {editable ? (
                <Button
                  disabled={dirty || !review.publishable}
                  onClick={() => setAction('submit')}
                >
                  Submit for approval
                </Button>
              ) : null}
              {mayDecide ? (
                <>
                  <Button
                    tone="primary"
                    disabled={!review.publishable}
                    onClick={() => setAction('publish')}
                  >
                    Approve and publish
                  </Button>
                  <Button tone="danger" onClick={() => setAction('reject')}>
                    Reject
                  </Button>
                </>
              ) : null}
              {(draft.status === 'DRAFT' || draft.status === 'SUBMITTED') &&
              can(me?.permissions, 'plan.edit') ? (
                <Button tone="ghost" onClick={() => setAction('discard')}>
                  Discard draft
                </Button>
              ) : null}
            </div>
            <p className="muted small">
              Submitted by {who(draft.submittedById)}
              {draft.submittedAt ? ` on ${formatDateTime(draft.submittedAt)}` : ''}.
            </p>
          </Card>
        </aside>
      </div>

      <ConfirmDialog
        open={action === 'submit'}
        title="Submit for approval?"
        confirmLabel="Submit"
        onClose={() => setAction(null)}
        onConfirm={async () => {
          onChanged(await api.post<PlanDraft>(`/admin/plan-drafts/${draft.id}/submit`));
          toast('success', 'Submitted. A second admin can now publish it.');
        }}
      >
        <p>You won’t be able to edit it while it waits, and you can’t approve it yourself.</p>
      </ConfirmDialog>

      <ConfirmDialog
        open={action === 'publish'}
        title={`Publish this change to ${draft.planName}?`}
        confirmLabel="Publish"
        onClose={() => setAction(null)}
        onConfirm={async () => {
          const next = await api.post<PlanDraft>(`/admin/plan-drafts/${draft.id}/publish`, {});
          onChanged(next);
          await reloadCatalogue();
          toast(
            'success',
            next.publishedVersion
              ? `Published as version ${next.publishedVersion}.`
              : 'Prices published.',
          );
        }}
      >
        <p>
          New purchases get it immediately. Members who already bought keep the version they
          paid for.
        </p>
      </ConfirmDialog>

      <ConfirmDialog
        open={action === 'reject'}
        title="Reject this draft?"
        confirmLabel="Reject"
        tone="danger"
        requireReason
        reasonLabel="Why (shown to the submitter)"
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          onChanged(await api.post<PlanDraft>(`/admin/plan-drafts/${draft.id}/reject`, { reason }));
          toast('success', 'Draft rejected.');
        }}
      />

      <ConfirmDialog
        open={action === 'discard'}
        title="Discard this draft?"
        confirmLabel="Discard"
        tone="danger"
        requireReason
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          onChanged(await api.post<PlanDraft>(`/admin/plan-drafts/${draft.id}/discard`, { reason }));
          toast('success', 'Draft discarded.');
        }}
      />
    </>
  );
}

function FeatureEditor({
  feature,
  value,
  current,
  editable,
  onChange,
}: {
  feature: FeatureDescriptor;
  value: EntitlementValue | undefined;
  current: EntitlementValue | undefined;
  editable: boolean;
  onChange: (value: EntitlementValue) => void;
}) {
  const changed = !sameValue(value, current);
  const id = `feature-${feature.key}`;

  let control: ReactNode;
  if (!editable) {
    control = <span>{describeValue(feature, value)}</span>;
  } else if (feature.kind === 'boolean') {
    const locked = feature.requiredOnEveryPlan === true;
    control = (
      <input
        id={id}
        type="checkbox"
        checked={value === true}
        disabled={locked}
        onChange={(e) => onChange(e.target.checked)}
      />
    );
  } else if (feature.kind === 'level') {
    control = (
      <select id={id} value={typeof value === 'string' ? value : ''} onChange={(e) => onChange(e.target.value)}>
        {(feature.levels ?? []).map((level) => (
          <option key={level} value={level}>
            {humanize(level)}
          </option>
        ))}
      </select>
    );
  } else {
    const limit: LimitValue =
      value && typeof value === 'object' ? (value as LimitValue) : { limit: 0 };
    const unlimited = limit.limit === null;
    const setNumber = (key: keyof LimitValue, raw: string) => {
      const next: LimitValue = { ...limit };
      if (raw === '') {
        if (key === 'limit') next.limit = 0;
        else delete next[key];
      } else {
        next[key] = Math.max(0, Math.trunc(Number(raw))) as never;
      }
      onChange(next);
    };
    control = (
      <span className="limit-editor">
        <label>
          <input
            type="checkbox"
            checked={unlimited}
            onChange={(e) =>
              onChange(e.target.checked ? { ...limit, limit: null } : { ...limit, limit: 0 })
            }
          />{' '}
          Unlimited
        </label>
        {!unlimited ? (
          <input
            id={id}
            aria-label={`${feature.label} limit`}
            inputMode="numeric"
            value={String(limit.limit ?? 0)}
            onChange={(e) => setNumber('limit', e.target.value)}
          />
        ) : (
          <input
            aria-label={`${feature.label} fair-use cap`}
            inputMode="numeric"
            placeholder="Fair-use cap (optional)"
            value={limit.fairUse === undefined ? '' : String(limit.fairUse)}
            onChange={(e) => setNumber('fairUse', e.target.value)}
          />
        )}
        {feature.kind === 'quota' && feature.period === 'SUBSCRIPTION' ? (
          <input
            aria-label={`${feature.label}: per how many months`}
            inputMode="numeric"
            placeholder="per N months"
            value={limit.perMonths === undefined ? '' : String(limit.perMonths)}
            onChange={(e) => setNumber('perMonths', e.target.value)}
          />
        ) : null}
        {feature.kind === 'quota' && feature.period !== 'SUBSCRIPTION' ? (
          <span className="muted small">per {feature.period?.toLowerCase()}</span>
        ) : null}
      </span>
    );
  }

  return (
    <div className={`feature-row ${changed ? 'changed' : ''}`}>
      <label htmlFor={id}>
        {feature.label}
        {feature.requiredOnEveryPlan ? (
          <span className="muted small"> · required on every plan</span>
        ) : null}
      </label>
      <div className="feature-control">
        {control}
        {changed ? (
          <span className="muted small">was {describeValue(feature, current)}</span>
        ) : null}
      </div>
    </div>
  );
}
