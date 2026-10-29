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
  /** The member's verified phone hash; null when there is none (always refused). */
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
  | { ok: true; windowEndsAt: Date }
  | { ok: false; reason: AttributionRejectReason; markRejected?: boolean };

const MS_PER_DAY = 24 * 60 * 60 * 1000;

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

  // A phone hash is required on every attribution, whatever the source: the
  // database column is NOT NULL, and one attribution per phone is how a second
  // account on the same number is caught. No verified phone, no credit.
  if (input.memberPhoneHash === null) {
    return { ok: false, reason: 'PHONE_NOT_VERIFIED' };
  }

  const windowEndsAt =
    input.source === 'ENTERED_AT_PAYMENT'
      ? new Date(input.now.getTime())
      : new Date(input.now.getTime() + input.creditWindowDays * MS_PER_DAY);

  return { ok: true, windowEndsAt };
}
