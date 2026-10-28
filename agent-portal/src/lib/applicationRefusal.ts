import { ApiError } from '../api/errors';
import type { AgentStatus } from '../api/types';

/** The application form's fields, in the order they are shown. */
export const APPLICATION_FIELDS = ['name', 'city', 'state', 'pan'] as const;
export type ApplicationField = (typeof APPLICATION_FIELDS)[number];

/**
 * What the portal shows when `POST /agent/application` is refused — the
 * table in docs/agent-program/FRONTEND_HANDOFF_DHATRI.md §4.2. Branches on
 * `code`, then on `agentStatus`; never on the message text (except to find
 * which fields a 400 names, since that is all a 400 carries).
 */
export type ApplicationRefusal =
  /** 401: the applicant's verified phone expired, or the token is invalid. */
  | { kind: 'verifyAgain' }
  /** 403 AGENT_NOT_ACTIVE + REJECTED: Rejected screen, no "Apply again". */
  | { kind: 'rejected' }
  /** 409 APPLICATION_EXISTS + PENDING_APPROVAL: the Pending screen. */
  | { kind: 'pending' }
  /** 409 APPLICATION_EXISTS + ACTIVE/SUSPENDED/TERMINATED: already an agent. */
  | { kind: 'alreadyAgent'; agentStatus: AgentStatus }
  /** 409 APPLICATION_EXISTS with no agentStatus: applied from another device. */
  | { kind: 'signInAgain' }
  /** 400 VALIDATION_FAILED: highlight these fields (may be empty). */
  | { kind: 'invalidFields'; fields: ApplicationField[] };

const ALREADY_AGENT: AgentStatus[] = ['ACTIVE', 'SUSPENDED', 'TERMINATED'];

/** Null when the error is not one of the documented refusals. */
export function applicationRefusal(error: unknown): ApplicationRefusal | null {
  if (!(error instanceof ApiError)) return null;
  if (error.status === 401) return { kind: 'verifyAgain' };
  if (error.status === 403 && error.code === 'AGENT_NOT_ACTIVE') {
    if (error.agentStatus === 'REJECTED') return { kind: 'rejected' };
    if (error.agentStatus && ALREADY_AGENT.includes(error.agentStatus)) {
      return { kind: 'alreadyAgent', agentStatus: error.agentStatus };
    }
    // No (or an unexpected) status: don't guess; signing in shows the truth.
    return { kind: 'signInAgain' };
  }
  if (error.status === 409 && error.code === 'APPLICATION_EXISTS') {
    if (error.agentStatus === 'PENDING_APPROVAL') return { kind: 'pending' };
    if (error.agentStatus && ALREADY_AGENT.includes(error.agentStatus)) {
      return { kind: 'alreadyAgent', agentStatus: error.agentStatus };
    }
    return { kind: 'signInAgain' };
  }
  if (error.status === 400 && error.code === 'VALIDATION_FAILED') {
    return { kind: 'invalidFields', fields: fieldsNamedIn(error.message) };
  }
  return null;
}

/**
 * The fields a 400 names. The response never repeats what was typed, only
 * which fields are wrong, so field names are all there is to find.
 */
function fieldsNamedIn(message: string): ApplicationField[] {
  const text = message.toLowerCase();
  return APPLICATION_FIELDS.filter((f) => new RegExp(`\\b${f}\\b`).test(text));
}
