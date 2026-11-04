import { ApiError } from '../api/errors';
import type { AgentConfig, AgentProfile, ClientDraft } from '../api/types';
import { errorMessage } from '../components/ErrorText';

/**
 * Clients are shown only when the server says so: `clients.enabled === true`
 * (a missing `clients` object, i.e. an older server, counts as off) and the
 * agent is ACTIVE or SUSPENDED. Other statuses answer 403 AGENT_NOT_ACTIVE.
 */
export function clientsAvailable(
  config: AgentConfig | null | undefined,
  agent: AgentProfile | null | undefined,
): boolean {
  if (config?.clients?.enabled !== true) return false;
  return agent?.status === 'ACTIVE' || agent?.status === 'SUSPENDED';
}

/** Open = DRAFT plus WAITING_FOR_CLIENT (what `draftLimit` counts). */
export function isOpen(draft: Pick<ClientDraft, 'status'>): boolean {
  return draft.status === 'DRAFT' || draft.status === 'WAITING_FOR_CLIENT';
}

/** Wording for the documented Way 2 refusals; anything else falls back. */
export function clientErrorMessage(error: unknown, draftLimit?: number | null): string {
  if (error instanceof ApiError) {
    switch (error.code) {
      case 'CLIENT_INVITES_DISABLED':
        return "This isn't available right now.";
      case 'AGENT_NOT_ACTIVE':
        return "Your account is paused; you can't add clients right now.";
      case 'CLIENT_DRAFT_EXISTS':
        return 'You have already added this number.';
      case 'CLIENT_DRAFT_LIMIT_REACHED':
        return draftLimit
          ? `You can have at most ${draftLimit} open clients. Submit, discard or wait for one to close.`
          : 'You have reached the limit of open clients. Submit, discard or wait for one to close.';
      case 'CLIENT_PHONE_UNAVAILABLE':
        return "This number can't be added.";
      case 'CLIENT_DRAFT_LOCKED':
        return "This client was already submitted (or has closed) and can't be changed.";
      case 'CLIENT_DRAFT_NOT_FOUND':
        return 'This client no longer exists.';
      case 'CONCURRENT_CHANGE':
        return 'Something changed at the same moment. Please try again.';
      case 'OTP_DELIVERY_UNAVAILABLE':
        return 'Only test numbers can be added for now.';
      case 'CLIENT_PROFILE_INCOMPLETE':
        return 'Some required details are still missing.';
    }
  }
  return errorMessage(error);
}

/** "5 required fields left", from the server's list only. */
export function missingText(missing: string[]): string {
  const n = missing.length;
  return n === 0 ? 'All required details are filled in' : `${n} required field${n === 1 ? '' : 's'} left`;
}
