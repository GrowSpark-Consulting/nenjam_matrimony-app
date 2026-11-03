/**
 * A client draft as the agent sees it (`ClientDraft` in the agent contract).
 *
 * Pure. The caller opens the sealed profile and passes it in; the view
 * drops it anyway once the draft is closed (or past its time), so a closed
 * draft never shows the client's details whatever the caller passed.
 * `missingRequired` lists the required fields (client-profile-required.ts)
 * still empty, so the portal can show what is left before submit.
 */
import { toIstDate } from '../agent/ist-date';
import type { AgentLocalizedText } from '../ports/agent-content.port';
import type {
  AgentClientDraftRecord,
  ClientDraftStatus,
} from '../ports/agent-client-ports';
import {
  missingRequiredClientFields,
  type ClientProfile,
} from './client-profile';
import { effectiveClientDraftStatus } from './decide-client-draft';

export interface ClientDraftView {
  id: string;
  status: ClientDraftStatus;
  statusLabel: AgentLocalizedText;
  displayName: string;
  phoneMasked: string;
  details: ClientProfile | null;
  /** Required fields still empty; [] once closed. */
  missingRequired: string[];
  editable: boolean;
  /** ISO-8601 UTC. */
  createdAt: string;
  /** Indian calendar dates, YYYY-MM-DD. */
  submittedOn: string | null;
  expiresOn: string;
  acceptedOn: string | null;
  /** The attribution id once ACCEPTED (`GET /agent/referrals/{id}`). */
  referralId: string | null;
}

export function clientDraftView(
  row: AgentClientDraftRecord,
  now: Date,
  options: {
    labels: Record<ClientDraftStatus, AgentLocalizedText>;
    /** The opened profile, or null when not opened. */
    details: ClientProfile | null;
  },
): ClientDraftView {
  const status = effectiveClientDraftStatus(row, now);
  const open = status === 'DRAFT' || status === 'WAITING_FOR_CLIENT';
  const details = open ? options.details : null;
  return {
    id: row.id,
    status,
    statusLabel: options.labels[status],
    displayName: row.displayName,
    phoneMasked: row.phoneMasked,
    details,
    missingRequired: details ? missingRequiredClientFields(details) : [],
    editable: status === 'DRAFT',
    createdAt: row.createdAt.toISOString(),
    submittedOn: row.submittedAt ? toIstDate(row.submittedAt) : null,
    expiresOn: toIstDate(row.expiresAt),
    acceptedOn: row.acceptedAt ? toIstDate(row.acceptedAt) : null,
    referralId: status === 'ACCEPTED' ? row.attributionId : null,
  };
}
