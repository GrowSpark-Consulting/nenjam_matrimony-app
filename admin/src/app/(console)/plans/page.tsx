'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
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
  PageHeader,
  useToast,
} from '@/components/ui';
import { bySection, describeValue } from '@/lib/entitlements';
import { formatDate, formatDateTime, formatPaise, humanize } from '@/lib/format';
import { can } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type { PlanDraft, PlanRow, PlansResponse } from '@/lib/types';
import { useApi } from '@/lib/use-api';

type Dialog =
  | { kind: 'display'; plan: PlanRow }
  | { kind: 'status'; plan: PlanRow }
  | { kind: 'draft'; plan: PlanRow }
  | null;

export default function PlansPage() {
  return (
    <RequirePermission permission="plan.view">
      <Plans />
    </RequirePermission>
  );
}

function Plans() {
  const { api, me } = useSession();
  const toast = useToast();
  const router = useRouter();
  const catalogue = useApi((client) => client.get<PlansResponse>('/admin/plans'), []);
  const drafts = useApi((client) => client.get<PlanDraft[]>('/admin/plan-drafts'), []);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [displayName, setDisplayName] = useState('');
  const [description, setDescription] = useState('');

  const mayEdit = can(me?.permissions, 'plan.edit');
  const mayPublish = can(me?.permissions, 'plan.publish');

  const openDisplay = (plan: PlanRow) => {
    setDisplayName(plan.name);
    setDescription(plan.description ?? '');
    setDialog({ kind: 'display', plan });
  };

  return (
    <>
      <PageHeader
        title="Plans"
        description="What each plan includes and costs. Changes members would see are made in a draft and published by a second admin; members keep the version they bought."
      />
      {catalogue.loading && !catalogue.data ? <Loading /> : null}
      {catalogue.error ? (
        <ErrorState message={catalogue.error} onRetry={catalogue.reload} />
      ) : null}

      {catalogue.data?.plans.map((plan) => (
        <Card
          key={plan.code}
          title={
            <>
              {plan.name} <span className="muted small">({plan.code})</span>{' '}
              <Badge value={plan.isActive ? 'ACTIVE' : 'EXPIRED'} label={plan.isActive ? 'on sale' : 'off sale'} />
            </>
          }
          actions={
            <div className="row-actions">
              {plan.openDraft ? (
                <Link className="btn btn-secondary" href={`/plans/draft/?id=${plan.openDraft.id}`}>
                  Open {plan.openDraft.status === 'SUBMITTED' ? 'submitted' : ''} draft
                </Link>
              ) : mayEdit ? (
                <Button tone="primary" onClick={() => setDialog({ kind: 'draft', plan })}>
                  Propose a change
                </Button>
              ) : null}
              {mayEdit ? <Button onClick={() => openDisplay(plan)}>Edit name</Button> : null}
              {mayPublish && !plan.isFree ? (
                <Button
                  tone={plan.isActive ? 'danger' : 'secondary'}
                  onClick={() => setDialog({ kind: 'status', plan })}
                >
                  {plan.isActive ? 'Stop selling' : 'Start selling'}
                </Button>
              ) : null}
            </div>
          }
        >
          {plan.description ? <p>{plan.description}</p> : null}
          <p className="muted small">
            {plan.activeSubscribers} active member{plan.activeSubscribers === 1 ? '' : 's'} ·{' '}
            {plan.currentVersion
              ? `entitlements version ${plan.currentVersion.version} since ${formatDate(plan.currentVersion.effectiveFrom)}`
              : 'no entitlement version yet'}
          </p>

          {plan.isFree ? null : (
            <div className="table-wrap">
              <table>
                <caption className="sr-only">{plan.name} prices</caption>
                <thead>
                  <tr>
                    <th scope="col">Length</th>
                    <th scope="col">Days (+ bonus)</th>
                    <th scope="col">Price</th>
                    <th scope="col">On sale</th>
                  </tr>
                </thead>
                <tbody>
                  {plan.durations.length === 0 ? (
                    <tr>
                      <td colSpan={4} className="muted">
                        No lengths defined.
                      </td>
                    </tr>
                  ) : null}
                  {plan.durations.map((d) => (
                    <tr key={d.months}>
                      <td>{d.months} months</td>
                      <td>
                        {d.durationDays}
                        {d.bonusDays ? ` + ${d.bonusDays}` : ''}
                      </td>
                      <td>{formatPaise(d.priceInPaise)}</td>
                      <td>{d.isActive ? 'Yes' : 'No'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {plan.currentVersion && catalogue.data ? (
            <details>
              <summary>What {plan.name} includes</summary>
              {bySection(catalogue.data.features).map(([section, features]) => (
                <div key={section} className="feature-section">
                  <h3>{humanize(section)}</h3>
                  <ul className="kv">
                    {features.map((feature) => (
                      <li key={feature.key}>
                        <span>{feature.label}</span>
                        <span>{describeValue(feature, plan.currentVersion!.entitlements[feature.key])}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </details>
          ) : null}

          {plan.versions.length > 0 ? (
            <details>
              <summary>Version history ({plan.versions.length})</summary>
              <ul className="history">
                {plan.versions.map((v) => (
                  <li key={v.id}>
                    <strong>v{v.version}</strong>{' '}
                    {v.isCurrent ? <Badge value="ACTIVE" label="current" /> : null}
                    {v.isScheduled ? <Badge value="PENDING" label="scheduled" /> : null}{' '}
                    <span className="muted">from {formatDateTime(v.effectiveFrom)}</span>
                    {v.changeNote ? <div>{v.changeNote}</div> : null}
                  </li>
                ))}
              </ul>
            </details>
          ) : null}
        </Card>
      ))}

      <Card title="Drafts">
        {drafts.loading && !drafts.data ? <Loading /> : null}
        {drafts.error ? <ErrorState message={drafts.error} onRetry={drafts.reload} /> : null}
        {drafts.data && drafts.data.length === 0 ? (
          <EmptyState title="No drafts yet">Propose a change on a plan to start one.</EmptyState>
        ) : null}
        {drafts.data && drafts.data.length > 0 ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">Plan</th>
                  <th scope="col">Change</th>
                  <th scope="col">Status</th>
                  <th scope="col">Updated</th>
                </tr>
              </thead>
              <tbody>
                {drafts.data.map((draft) => (
                  <tr key={draft.id}>
                    <td>{draft.planName}</td>
                    <td>
                      <Link href={`/plans/draft/?id=${draft.id}`}>{draft.changeNote}</Link>
                    </td>
                    <td>
                      <Badge value={draft.status} />
                    </td>
                    <td>{formatDateTime(draft.updatedAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
      </Card>

      <ConfirmDialog
        open={dialog?.kind === 'draft'}
        title={dialog ? `Propose a change to ${dialog.plan.name}` : ''}
        confirmLabel="Start draft"
        requireReason
        reasonLabel="What is this change for?"
        onClose={() => setDialog(null)}
        onConfirm={async (changeNote) => {
          if (dialog?.kind !== 'draft') return;
          const draft = await api.post<PlanDraft>('/admin/plan-drafts', {
            planCode: dialog.plan.code,
            changeNote,
          });
          toast('success', 'Draft started.');
          router.push(`/plans/draft/?id=${draft.id}`);
        }}
      >
        <p className="muted">
          The draft starts as an exact copy of the plan. Nothing changes for members until a
          second admin publishes it.
        </p>
      </ConfirmDialog>

      <ConfirmDialog
        open={dialog?.kind === 'display'}
        title={dialog ? `Edit ${dialog.plan.name}` : ''}
        confirmLabel="Save"
        requireReason
        onClose={() => setDialog(null)}
        onConfirm={async (reason) => {
          if (dialog?.kind !== 'display') return;
          await api.patch(`/admin/plans/${dialog.plan.code}/display`, {
            displayName,
            description,
            reason,
          });
          toast('success', 'Plan details saved.');
          await catalogue.reload();
        }}
      >
        <Field label="Name">
          {(props) => (
            <input
              {...props}
              value={displayName}
              maxLength={60}
              onChange={(e) => setDisplayName(e.target.value)}
              required
            />
          )}
        </Field>
        <Field label="Description">
          {(props) => (
            <textarea
              {...props}
              rows={3}
              maxLength={500}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          )}
        </Field>
      </ConfirmDialog>

      <ConfirmDialog
        open={dialog?.kind === 'status'}
        title={
          dialog
            ? dialog.plan.isActive
              ? `Stop selling ${dialog.plan.name}?`
              : `Start selling ${dialog.plan.name}?`
            : ''
        }
        confirmLabel={dialog?.plan.isActive ? 'Stop selling' : 'Start selling'}
        tone={dialog?.plan.isActive ? 'danger' : 'primary'}
        requireReason
        onClose={() => setDialog(null)}
        onConfirm={async (reason) => {
          if (dialog?.kind !== 'status') return;
          await api.post(`/admin/plans/${dialog.plan.code}/status`, {
            isActive: !dialog.plan.isActive,
            reason,
          });
          toast('success', dialog.plan.isActive ? 'Plan taken off sale.' : 'Plan on sale.');
          await catalogue.reload();
        }}
      >
        <p>
          {dialog?.plan.isActive
            ? 'New purchases stop immediately. Members who already have this plan keep it until it ends.'
            : 'Members can buy the lengths that are priced and on sale.'}
        </p>
      </ConfirmDialog>
    </>
  );
}
