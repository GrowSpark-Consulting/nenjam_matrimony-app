import { pickLabel } from '../lib/labels';
import { usePortal } from '../state/PortalContext';

/**
 * Status screens from `GET /agent/me`, labelled from `GET /agent/config`.
 *
 * Rejected: shows `rejectionReason`. There is no "Apply again" button yet —
 * whether a rejected agent may re-apply is pending with Raja.
 */
export function StatusPage() {
  const { agent, config } = usePortal();
  if (!agent) return null;
  const label = pickLabel(config?.statusLabels[agent.status] ?? agent.statusLabel, agent.status);
  return (
    <section>
      <h1>{label}</h1>
      {agent.status === 'PENDING_APPROVAL' && <p>We're reviewing your application.</p>}
      {agent.status === 'REJECTED' && agent.rejectionReason && (
        <p>
          <strong>Reason:</strong> {agent.rejectionReason}
        </p>
      )}
      {agent.status === 'SUSPENDED' && (
        <p>Your account is paused. You can still see your details, but sharing is turned off.</p>
      )}
      {agent.status === 'TERMINATED' && (
        <p>Your account is closed. Your earnings, balance and payouts stay visible.</p>
      )}
      <dl className="facts">
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
    </section>
  );
}
