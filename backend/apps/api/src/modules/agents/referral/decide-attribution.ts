/**
 * Decides whether a member may be credited to an agent, and until when.
 *
 * Pure: the caller does every lookup and passes the answers in, together with
 * `now` and the credit window (a setting, never a constant here).
 */

export type AttributionSource =
  'CODE_AT_SIGNUP' | 'LINK_OR_QR' | 'ENTERED_AT_PAYMENT';

export interface AttributionInput {
  source: AttributionSource;
  codeFound: boolean;
  codeActive: boolean;
  /** AgentStatus of the code's agent, e.g. ACTIVE, SUSPENDED. */
  agentStatus: string;
  memberPhoneHash: string | null;
  agentPhoneHash: string | null;
  /** The member already has an attribution: the first agent always stays. */
  memberAlreadyAttributed: boolean;
  /** Another account with this phone hash was already credited. */
  phoneAlreadyCredited: boolean;
  /** Any EARLIER successful payment by this member. */
  memberHasPaid: boolean;
  now: Date;
  creditWindowDays: number;
}

export type AttributionRejectReason =
  | 'INVALID_CODE'
  | 'CODE_INACTIVE'
  | 'AGENT_NOT_ACTIVE'
  | 'SELF_REFERRAL'
  | 'ALREADY_ATTRIBUTED'
  | 'PHONE_ALREADY_CREDITED'
  | 'ALREADY_PAID'
  | 'PHONE_NOT_VERIFIED';

export type AttributionDecision =
  | { ok: true; windowEndsAt: Date; needsReview?: boolean }
  | { ok: false; reason: AttributionRejectReason; markRejected?: boolean };

const MS_PER_DAY = 24 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// PENDING DECISION (Raja): what to do when the member's phone hash is missing.
// Signup sources cannot be trusted without a verified phone, so they are
// refused; a code entered at payment is accepted but flagged for admin review.
// This is the ONLY place that rule lives; change it here.
// ---------------------------------------------------------------------------
function decideMissingPhoneHash(
  source: AttributionSource,
): { ok: false; reason: 'PHONE_NOT_VERIFIED' } | { needsReview: true } {
  return source === 'ENTERED_AT_PAYMENT'
    ? { needsReview: true }
    : { ok: false, reason: 'PHONE_NOT_VERIFIED' };
}

export function decideAttribution(
  input: AttributionInput,
): AttributionDecision {
  if (
    !Number.isSafeInteger(input.creditWindowDays) ||
    input.creditWindowDays < 0
  ) {
    throw new RangeError('creditWindowDays must be a non-negative integer.');
  }
  if (Number.isNaN(input.now.getTime())) {
    throw new RangeError('now must be a valid date.');
  }

  if (!input.codeFound) return { ok: false, reason: 'INVALID_CODE' };
  if (!input.codeActive) return { ok: false, reason: 'CODE_INACTIVE' };
  if (input.agentStatus !== 'ACTIVE') {
    return { ok: false, reason: 'AGENT_NOT_ACTIVE' };
  }
  if (
    input.memberPhoneHash !== null &&
    input.agentPhoneHash !== null &&
    input.memberPhoneHash === input.agentPhoneHash
  ) {
    return { ok: false, reason: 'SELF_REFERRAL', markRejected: true };
  }
  if (input.memberAlreadyAttributed) {
    return { ok: false, reason: 'ALREADY_ATTRIBUTED' };
  }
  if (input.phoneAlreadyCredited) {
    return { ok: false, reason: 'PHONE_ALREADY_CREDITED' };
  }
  if (input.memberHasPaid) return { ok: false, reason: 'ALREADY_PAID' };

  let needsReview = false;
  if (input.memberPhoneHash === null) {
    const missing = decideMissingPhoneHash(input.source);
    if ('ok' in missing) return missing;
    needsReview = missing.needsReview;
  }

  const windowEndsAt =
    input.source === 'ENTERED_AT_PAYMENT'
      ? new Date(input.now.getTime())
      : new Date(input.now.getTime() + input.creditWindowDays * MS_PER_DAY);

  return needsReview
    ? { ok: true, windowEndsAt, needsReview: true }
    : { ok: true, windowEndsAt };
}
