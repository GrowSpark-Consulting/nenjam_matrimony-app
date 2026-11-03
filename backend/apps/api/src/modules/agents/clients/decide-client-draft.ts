/**
 * The rules of agent-added clients ("Way 2") as pure functions: may an agent
 * add (or submit) this phone, and may this invitation be accepted.
 *
 * The caller does every lookup and passes the answers in, together with
 * `now` and the settings (never constants here).
 *
 * The phone refusals keep their internal reason (`refusal`) for the audit
 * row, but the agent is only ever told CLIENT_PHONE_UNAVAILABLE: whether a
 * phone belongs to a member must not leak to an agent.
 */
import type { ClientDraftStatus } from '../ports/agent-client-ports';

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Why a phone cannot be added. Internal: audit metadata only. */
export type ClientPhoneRefusal =
  /** The phone already belongs to a member account (staff and deleted ones included). */
  | 'MEMBER'
  /** The phone is already credited to an agent. */
  | 'CREDITED'
  /** It is the agent's own phone. */
  | 'OWN_PHONE'
  /** This client rejected this agent before. */
  | 'REJECTED_BEFORE';

export interface ClientPhoneFacts {
  /** A one-time code can reach the phone (with the dummy code: an approved test number). */
  canReach: boolean;
  phoneIsMember: boolean;
  phoneCredited: boolean;
  isAgentsOwnPhone: boolean;
  rejectedBefore: boolean;
}

export type ClientDraftDecision =
  | { ok: true }
  | {
      ok: false;
      reason: 'DELIVERY_UNAVAILABLE' | 'DRAFT_EXISTS' | 'LIMIT_REACHED';
    }
  | { ok: false; reason: 'PHONE_UNAVAILABLE'; refusal: ClientPhoneRefusal };

function phoneRefusal(facts: ClientPhoneFacts): ClientPhoneRefusal | null {
  if (facts.isAgentsOwnPhone) return 'OWN_PHONE';
  if (facts.rejectedBefore) return 'REJECTED_BEFORE';
  if (facts.phoneIsMember) return 'MEMBER';
  if (facts.phoneCredited) return 'CREDITED';
  return null;
}

/**
 * Adding a client. The order is deliberate: a phone no code can reach is
 * refused before anything is looked up about it, so for every number that
 * is not an approved test number the answer is the same.
 */
export function decideClientDraftCreate(
  input: ClientPhoneFacts & {
    /** This agent already has an open draft for the phone. */
    hasOpenDraftForPhone: boolean;
    /** The agent's open drafts right now. */
    openCount: number;
    /** `agent.client_draft_limit`. */
    draftLimit: number;
  },
): ClientDraftDecision {
  if (!Number.isSafeInteger(input.draftLimit) || input.draftLimit < 0) {
    throw new RangeError('draftLimit must be a non-negative integer.');
  }
  if (!input.canReach) return { ok: false, reason: 'DELIVERY_UNAVAILABLE' };
  if (input.hasOpenDraftForPhone) return { ok: false, reason: 'DRAFT_EXISTS' };
  if (input.openCount >= input.draftLimit) {
    return { ok: false, reason: 'LIMIT_REACHED' };
  }
  const refusal = phoneRefusal(input);
  return refusal === null
    ? { ok: true }
    : { ok: false, reason: 'PHONE_UNAVAILABLE', refusal };
}

/** Submitting a DRAFT: the phone is checked again (it may have joined since). */
export function decideClientDraftSubmit(
  input: ClientPhoneFacts,
): ClientDraftDecision {
  if (!input.canReach) return { ok: false, reason: 'DELIVERY_UNAVAILABLE' };
  const refusal = phoneRefusal(input);
  return refusal === null
    ? { ok: true }
    : { ok: false, reason: 'PHONE_UNAVAILABLE', refusal };
}

/** When a draft created or submitted at `from` stops being open. */
export function clientDraftExpiresAt(from: Date, expiryDays: number): Date {
  if (!Number.isSafeInteger(expiryDays) || expiryDays < 1) {
    throw new RangeError('expiryDays must be an integer >= 1.');
  }
  return new Date(from.getTime() + expiryDays * MS_PER_DAY);
}

/** The status the agent sees: an open draft past its time is EXPIRED, whether or not the job has run. */
export function effectiveClientDraftStatus(
  row: { status: ClientDraftStatus; expiresAt: Date },
  now: Date,
): ClientDraftStatus {
  const open = row.status === 'DRAFT' || row.status === 'WAITING_FOR_CLIENT';
  return open && now.getTime() >= row.expiresAt.getTime()
    ? 'EXPIRED'
    : row.status;
}

export interface ClientAcceptInput {
  status: ClientDraftStatus;
  expiresAt: Date;
  now: Date;
  /** The adding agent's status; '' when the agent is gone. */
  agentStatus: string;
  /** An ACCEPTED draft's member still exists (a repeated accept). */
  acceptedMemberExists: boolean;
  /** The phone already has a member account. */
  phoneIsMember: boolean;
  /** The phone is already credited to an agent (it had an account before). */
  phoneCredited: boolean;
  /** `referral.credit_window_days`. */
  creditWindowDays: number;
}

export type ClientAcceptDecision =
  /** Create the member and credit the agent until `windowEndsAt`. */
  | { kind: 'ACCEPT'; windowEndsAt: Date }
  /** Already accepted by this phone (a lost response): sign her in again. */
  | { kind: 'REPEAT' }
  /** UNAVAILABLE: expired, closed or its agent not active. ALREADY_MEMBER: close it and send her to sign in. */
  | { kind: 'REFUSE'; reason: 'UNAVAILABLE' | 'ALREADY_MEMBER' };

/**
 * Accepting an invitation. The expiry is judged HERE, from `expiresAt`, never
 * from whether the daily job has closed the draft yet.
 */
export function decideClientAccept(
  input: ClientAcceptInput,
): ClientAcceptDecision {
  if (
    !Number.isSafeInteger(input.creditWindowDays) ||
    input.creditWindowDays < 0
  ) {
    throw new RangeError('creditWindowDays must be a non-negative integer.');
  }
  if (input.status === 'ACCEPTED') {
    return input.acceptedMemberExists
      ? { kind: 'REPEAT' }
      : { kind: 'REFUSE', reason: 'UNAVAILABLE' };
  }
  if (input.status !== 'WAITING_FOR_CLIENT') {
    return { kind: 'REFUSE', reason: 'UNAVAILABLE' };
  }
  if (input.now.getTime() >= input.expiresAt.getTime()) {
    return { kind: 'REFUSE', reason: 'UNAVAILABLE' };
  }
  if (input.agentStatus !== 'ACTIVE') {
    return { kind: 'REFUSE', reason: 'UNAVAILABLE' };
  }
  if (input.phoneIsMember || input.phoneCredited) {
    return { kind: 'REFUSE', reason: 'ALREADY_MEMBER' };
  }
  return {
    kind: 'ACCEPT',
    windowEndsAt: new Date(
      input.now.getTime() + input.creditWindowDays * MS_PER_DAY,
    ),
  };
}
