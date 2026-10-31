'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useRef, useState } from 'react';
import { RequirePermission } from '@/components/AppShell';
import {
  Badge,
  Button,
  Card,
  ConfirmDialog,
  ErrorState,
  Loading,
  PageHeader,
  useToast,
} from '@/components/ui';
import {
  agentStatusLabel,
  canDecide,
  manageActions,
  REVEAL_FIELDS,
  type RevealField,
} from '@/lib/agents';
import { formatDateTime, humanize } from '@/lib/format';
import { can } from '@/lib/permissions';
import { useSession } from '@/lib/session';
import type { AgentDetail, RevealedValues } from '@/lib/types';
import { useApi } from '@/lib/use-api';

export default function AgentViewPage() {
  return (
    <RequirePermission permission="agent.view">
      <Suspense fallback={<Loading />}>
        <AgentView />
      </Suspense>
    </RequirePermission>
  );
}

function AgentView() {
  const id = useSearchParams().get('id') ?? '';
  const { api, me } = useSession();
  const toast = useToast();
  const agent = useApi((client) => client.get<AgentDetail>(`/admin/agents/${id}`), [id]);
  type Action =
    | 'approve'
    | 'reject'
    | 'pause'
    | 'resume'
    | 'terminate'
    | 'replaceCode'
    | 'verifyPayout'
    | 'verifyPan'
    | 'reveal';
  const [action, setAction] = useState<Action | null>(null);
  const [fields, setFields] = useState<RevealField[]>(['PHONE']);
  // The revealed values live only in this state, are shown once and are
  // dropped when the dialog closes. Never stored, logged or put in the URL.
  const [revealed, setRevealed] = useState<RevealedValues | null>(null);

  if (!id) return <ErrorState message="No agent id in the address." />;
  if (agent.loading && !agent.data) return <Loading />;
  if (agent.error) return <ErrorState message={agent.error} onRetry={agent.reload} />;
  const a = agent.data;
  if (!a) return null;

  const decide = canDecide(a.status) && can(me?.permissions, 'agent.approve');
  const manage = can(me?.permissions, 'agent.manage') ? manageActions(a.status) : [];
  const canVerify = can(me?.permissions, 'agent.payout_details.verify');
  const canReveal = can(me?.permissions, 'agent.pii.reveal');
  const post = async (path: string, reason: string) =>
    agent.setData(await api.post<AgentDetail>(`/admin/agents/${a.id}/${path}`, { reason }));

  return (
    <>
      <PageHeader
        title={a.name}
        description={
          <>
            <Badge value={a.status} label={agentStatusLabel(a.status)} /> · {a.city}, {a.state} ·
            applied {formatDateTime(a.createdAt)}
          </>
        }
        actions={
          <div className="row-actions">
            <Link href="/agents/">Back</Link>
            {decide ? (
              <>
                <Button tone="primary" onClick={() => setAction('approve')}>
                  Approve
                </Button>
                <Button tone="danger" onClick={() => setAction('reject')}>
                  Reject
                </Button>
              </>
            ) : null}
            {manage.includes('pause') ? (
              <Button onClick={() => setAction('pause')}>Pause</Button>
            ) : null}
            {manage.includes('resume') ? (
              <Button tone="primary" onClick={() => setAction('resume')}>
                Resume
              </Button>
            ) : null}
            {manage.includes('replaceCode') ? (
              <Button onClick={() => setAction('replaceCode')}>Replace code</Button>
            ) : null}
            {manage.includes('terminate') ? (
              <Button tone="danger" onClick={() => setAction('terminate')}>
                Terminate
              </Button>
            ) : null}
          </div>
        }
      />

      {a.status === 'REJECTED' && a.rejectionReason ? (
        <Card title="Rejected">
          <p>{a.rejectionReason}</p>
          <p className="muted small">The applicant sees this reason and may apply again.</p>
        </Card>
      ) : null}

      <div className="grid">
        <Card title="Agent">
          <ul className="kv">
            <li>
              <span>Phone</span>
              <span>{a.phoneMasked}</span>
            </li>
            <li>
              <span>Place</span>
              <span>
                {a.city}, {a.state}
              </span>
            </li>
            <li>
              <span>Approved</span>
              <span>{formatDateTime(a.approvedAt)}</span>
            </li>
            <li>
              <span>Agent id</span>
              <code>{a.id}</code>
            </li>
          </ul>
        </Card>
        <Card title="PAN and payout">
          <div className="row-actions">
            {canVerify && a.panOnFile && !a.panVerifiedAt ? (
              <Button onClick={() => setAction('verifyPan')}>Mark PAN verified</Button>
            ) : null}
            {canVerify && a.payoutDetails && !a.payoutDetails.verifiedAt ? (
              <Button onClick={() => setAction('verifyPayout')}>
                Mark payout details verified
              </Button>
            ) : null}
            {canReveal ? (
              <Button
                onClick={() => {
                  setFields(['PHONE']);
                  setAction('reveal');
                }}
              >
                Reveal full details
              </Button>
            ) : null}
          </div>
          <ul className="kv">
            <li>
              <span>PAN</span>
              <span>
                {a.panOnFile ? `on file${a.panLast4 ? ` (…${a.panLast4})` : ''}` : 'not given'}
                {a.panVerifiedAt ? ` · verified ${formatDateTime(a.panVerifiedAt)}` : ''}
              </span>
            </li>
            <li>
              <span>Payout details</span>
              <span>
                {a.payoutDetails
                  ? `${a.payoutDetails.method} ${a.payoutDetails.display}`
                  : 'not set'}
              </span>
            </li>
            {a.payoutDetails ? (
              <li>
                <span>Payout verified</span>
                <span>
                  {a.payoutDetails.verifiedAt
                    ? formatDateTime(a.payoutDetails.verifiedAt)
                    : `no (changed ${formatDateTime(a.payoutDetails.changedAt)})`}
                </span>
              </li>
            ) : null}
          </ul>
        </Card>
      </div>

      <div className="grid">
        <Card title="Referral codes">
          {a.codes.length === 0 ? (
            <p className="muted">
              {a.status === 'PENDING_APPROVAL'
                ? 'The first code is issued on approval.'
                : 'No codes.'}
            </p>
          ) : (
            <ul className="kv">
              {a.codes.map((c) => (
                <li key={c.id}>
                  <code>{c.code}</code>
                  <span>
                    {c.isPrimary ? 'primary · ' : ''}
                    {c.isActive ? 'active' : 'inactive'} · {formatDateTime(c.createdAt)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <Card title="Referrals">
          <ul className="kv">
            <li>
              <span>Members referred</span>
              <span>{a.counts.referrals}</span>
            </li>
            {Object.entries(a.counts.byAttributionStatus).map(([status, count]) => (
              <li key={status}>
                <span>{humanize(status)}</span>
                <span>{count}</span>
              </li>
            ))}
            <li>
              <span>Needing review</span>
              <span>{a.counts.needsReview}</span>
            </li>
          </ul>
          <p className="muted small">Commissions appear here once the commission tables are live.</p>
        </Card>
      </div>

      <Card title="History">
        {a.statusHistory.length === 0 ? (
          <p className="muted">No status changes yet.</p>
        ) : (
          <ol className="timeline">
            {a.statusHistory.map((h, index) => (
              <li key={`${h.at}-${index}`}>
                <strong>
                  {agentStatusLabel(h.from)} → {agentStatusLabel(h.to)}
                </strong>{' '}
                <span className="muted">
                  {formatDateTime(h.at)} · {humanize(h.actorType)}
                </span>
                {h.reason ? <div>{h.reason}</div> : null}
              </li>
            ))}
          </ol>
        )}
      </Card>

      <ConfirmDialog
        open={action === 'pause'}
        title={`Pause ${a.name}?`}
        confirmLabel="Pause"
        requireReason
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          await post('pause', reason);
          toast('success', `${a.name} is paused.`);
        }}
      >
        <p>A paused agent can&apos;t share codes or sign in to work. You can resume them later.</p>
      </ConfirmDialog>

      <ConfirmDialog
        open={action === 'resume'}
        title={`Resume ${a.name}?`}
        confirmLabel="Resume"
        requireReason
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          await post('resume', reason);
          toast('success', `${a.name} is active again.`);
        }}
      />

      <ConfirmDialog
        open={action === 'terminate'}
        title={`Terminate ${a.name}?`}
        confirmLabel="Terminate"
        tone="danger"
        requireReason
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          await post('terminate', reason);
          toast('success', `${a.name} is terminated.`);
        }}
      >
        <p>
          This is final: a terminated agent can&apos;t be reactivated, and their commission that is
          still waiting stays frozen until it is decided. Commission already approved is still
          paid.
        </p>
      </ConfirmDialog>

      <ConfirmDialog
        open={action === 'replaceCode'}
        title={`Replace ${a.name}’s referral code?`}
        confirmLabel="Replace code"
        requireReason
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          await api.post(`/admin/agents/${a.id}/codes/replace`, { reason });
          agent.reload();
          toast('success', 'A new primary code was issued.');
        }}
      >
        <p>
          The agent gets a new primary code. The old code stops working for new members; members
          already linked to the agent stay linked.
        </p>
      </ConfirmDialog>

      <ConfirmDialog
        open={action === 'verifyPan'}
        title="Mark the PAN as verified?"
        confirmLabel="Mark verified"
        requireReason
        reasonLabel="How it was checked (kept in the audit log)"
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          await post('pan/verify', reason);
          toast('success', 'PAN marked as verified.');
        }}
      />

      <ConfirmDialog
        open={action === 'verifyPayout'}
        title="Mark the payout details as verified?"
        confirmLabel="Mark verified"
        requireReason
        reasonLabel="How it was checked (kept in the audit log)"
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          await post('payout-details/verify', reason);
          toast('success', 'Payout details marked as verified.');
        }}
      />

      <ConfirmDialog
        open={action === 'reveal'}
        title="Reveal full details"
        confirmLabel="Reveal"
        requireReason
        reasonLabel="Why you need to see them (kept in the audit log)"
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          if (fields.length === 0) throw new Error('Choose at least one thing to reveal.');
          setRevealed(
            await api.post<RevealedValues>(`/admin/agents/${a.id}/reveal`, { fields, reason }),
          );
        }}
      >
        <p>
          Shown once, never saved. Each item you reveal is recorded in the audit log, and you may
          be asked for a fresh authenticator code.
        </p>
        <fieldset className="stack">
          {REVEAL_FIELDS.map((f) => (
            <label key={f.value}>
              <input
                type="checkbox"
                checked={fields.includes(f.value)}
                onChange={(e) =>
                  setFields((list) =>
                    e.target.checked ? [...list, f.value] : list.filter((x) => x !== f.value),
                  )
                }
              />{' '}
              {f.label}
            </label>
          ))}
        </fieldset>
      </ConfirmDialog>

      <RevealedDialog values={revealed} onClose={() => setRevealed(null)} />

      <ConfirmDialog
        open={action === 'approve'}
        title={`Approve ${a.name}?`}
        confirmLabel="Approve"
        requireReason
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          agent.setData(
            await api.post<AgentDetail>(`/admin/agents/${a.id}/approve`, { reason }),
          );
          toast('success', `${a.name} is approved and has a referral code.`);
        }}
      >
        <p>
          The agent becomes active and gets their first referral code (NM…), which they can
          share straight away.
        </p>
      </ConfirmDialog>

      <ConfirmDialog
        open={action === 'reject'}
        title={`Reject ${a.name}’s application?`}
        confirmLabel="Reject"
        tone="danger"
        requireReason
        reasonLabel="Reason (shown to the applicant, and kept in the audit log)"
        onClose={() => setAction(null)}
        onConfirm={async (reason) => {
          agent.setData(
            await api.post<AgentDetail>(`/admin/agents/${a.id}/reject`, { reason }),
          );
          toast('success', 'Application rejected.');
        }}
      >
        <p>The applicant sees your reason and may apply again later.</p>
      </ConfirmDialog>
    </>
  );
}

/** The revealed values, once. Closing the dialog drops them from memory. */
function RevealedDialog({
  values,
  onClose,
}: {
  values: RevealedValues | null;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (values && !dialog.open) dialog.showModal();
    else if (!values && dialog.open) dialog.close();
  }, [values]);

  const payout = values?.payoutDetails;
  return (
    <dialog ref={ref} className="dialog" onClose={onClose} aria-labelledby="reveal-title">
      <h2 id="reveal-title">Revealed details</h2>
      {values ? (
        <>
          <ul className="kv">
            {values.phone ? (
              <li>
                <span>Phone</span>
                <code>{values.phone}</code>
              </li>
            ) : null}
            {values.pan ? (
              <li>
                <span>PAN</span>
                <code>{values.pan}</code>
              </li>
            ) : null}
            {payout?.upi ? (
              <li>
                <span>UPI</span>
                <code>{payout.upi.vpa}</code>
              </li>
            ) : null}
            {payout?.bank ? (
              <>
                <li>
                  <span>Account holder</span>
                  <span>{payout.bank.accountHolderName}</span>
                </li>
                <li>
                  <span>Account number</span>
                  <code>{payout.bank.accountNumber}</code>
                </li>
                <li>
                  <span>IFSC</span>
                  <code>{payout.bank.ifsc}</code>
                </li>
              </>
            ) : null}
          </ul>
          <p className="muted small">
            Shown once at {formatDateTime(values.revealedAt)}. It is not saved; close this window
            when you are done.
          </p>
        </>
      ) : null}
      <div className="dialog-actions">
        <Button tone="primary" onClick={onClose}>
          Close
        </Button>
      </div>
    </dialog>
  );
}
