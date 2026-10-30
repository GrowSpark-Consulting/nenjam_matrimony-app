import { Link } from 'react-router-dom';
import { PageHeader } from '../components/ui';
import { pickLabel } from '../lib/labels';
import { usePortal } from '../state/PortalContext';

/**
 * Status screens from `GET /agent/me`, labelled from `GET /agent/config`.
 *
 * Rejected: shows `rejectionReason` and an "Apply again" button (Raja
 * approved re-applying; the server still decides and may refuse).
 */
export function StatusPage() {
  const { agent, config } = usePortal();
  if (!agent) return null;
  const label = pickLabel(config?.statusLabels[agent.status] ?? agent.statusLabel, agent.status);
  return (
    <>
      <PageHeader title={label} />
      {agent.status === 'PENDING_APPROVAL' && <p>We're reviewing your application.</p>}
      {agent.status === 'REJECTED' && agent.rejectionReason && (
        <p className="notice">
          <strong>Reason:</strong> {agent.rejectionReason}
        </p>
      )}
      {agent.status === 'REJECTED' && (
        <p>
          <Link to="/apply" className="button">
            Apply again
          </Link>
        </p>
      )}
      {agent.status === 'SUSPENDED' && (
        <p>Your account is paused. You can still see your details, but sharing is turned off.</p>
      )}
      {agent.status === 'TERMINATED' && (
        <p>Your account is closed. Your earnings, balance and payouts stay visible.</p>
      )}
      <dl className="facts card">
        <dt>Name</dt>
        <dd>{agent.name}</dd>
        <dt>Phone</dt>
        <dd>{agent.phoneMasked}</dd>
        <dt>City</dt>
        <dd>
          {agent.city}, {agent.state}
        </dd>
        {agent.panLast4 && (
          <>
            <dt>PAN</dt>
            <dd>******{agent.panLast4}</dd>
          </>
        )}
      </dl>
    </>
  );
}
