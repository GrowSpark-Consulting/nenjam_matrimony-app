/**
 * The ONLY shape an agent ever sees about a person they referred.
 *
 * The output is built by explicitly picking each field below; it is never a
 * spread or a delete-from-input, so a field added to the input later cannot
 * reach an agent by accident. Plain types only — callers do the lookups and
 * hand this module already-resolved values (including `age`).
 */

export type ReferralStage = 'REGISTERED' | 'PROFILE_COMPLETE' | 'PURCHASED';

/** Commission states as stored internally, including review / fraud states. */
export type InternalCommissionStatus =
  | 'ON_HOLD'
  | 'AWAITING_VERIFICATION'
  | 'IN_REVIEW'
  | 'FROZEN'
  | 'READY'
  | 'APPROVED'
  | 'PAID'
  | 'CANCELLED'
  | 'REVERSED';

/** The only commission states an agent is ever shown. */
export type PublicCommissionStatus =
  'ON_HOLD' | 'APPROVED' | 'PAID' | 'CANCELLED';

/**
 * Internal -> public. Easy to change in one place. Internal review and
 * fraud-flag states collapse into ON_HOLD so agents never see them.
 */
export const COMMISSION_STATUS_PUBLIC_MAP: Readonly<
  Record<InternalCommissionStatus, PublicCommissionStatus>
> = {
  ON_HOLD: 'ON_HOLD',
  AWAITING_VERIFICATION: 'ON_HOLD',
  IN_REVIEW: 'ON_HOLD',
  FROZEN: 'ON_HOLD',
  READY: 'ON_HOLD',
  APPROVED: 'APPROVED',
  PAID: 'PAID',
  CANCELLED: 'CANCELLED',
  REVERSED: 'CANCELLED',
};

/** What the caller supplies. Not a Prisma type; extra fields are ignored. */
export interface ReferralViewSource {
  /** The attribution id, never the user id. */
  attributionId: string;
  firstName: string;
  lastName?: string | null;
  /** E.164, e.g. +919876543210. Only ever shown masked. */
  phoneE164: string;
  /** Supplied by the caller, already computed. */
  age: number;
  city: string;
  signedUpAt: Date | string;
  stage: ReferralStage;
  profileCompletenessPct: number;
  planName?: string | null;
  purchasedAt?: Date | string | null;
  commissionStatus?: InternalCommissionStatus | null;
}

export interface AgentReferralView {
  id: string;
  displayName: string;
  age: number;
  city: string;
  signedUpAt: string;
  stage: ReferralStage;
  profileCompletenessPct: number;
  planName: string | null;
  purchasedAt: string | null;
  commissionStatus: PublicCommissionStatus | null;
  maskedPhone: string;
}

/** The complete allow-list, in output order. */
export const AGENT_REFERRAL_VIEW_FIELDS = [
  'id',
  'displayName',
  'age',
  'city',
  'signedUpAt',
  'stage',
  'profileCompletenessPct',
  'planName',
  'purchasedAt',
  'commissionStatus',
  'maskedPhone',
] as const satisfies readonly (keyof AgentReferralView)[];

/** Shown for anything that is not a well-formed +91 number. */
export const FULLY_MASKED_PHONE = '**********';

const INDIAN_E164 = /^\+91(\d{10})$/;

/**
 * "+919876543210" -> "+91 98***210". Spaces, dashes and parentheses are
 * ignored. Anything else (malformed, short, empty, non-+91) returns a fully
 * masked string; never throws and never reveals a digit in that case.
 */
export function maskPhone(phone: string | null | undefined): string {
  if (typeof phone !== 'string') return FULLY_MASKED_PHONE;
  const match = INDIAN_E164.exec(phone.replace(/[\s\-()]/g, ''));
  if (!match) return FULLY_MASKED_PHONE;
  const digits = match[1];
  return `+91 ${digits.slice(0, 2)}***${digits.slice(-3)}`;
}

const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

function firstGrapheme(value: string): string {
  for (const { segment } of segmenter.segment(value)) return segment;
  return '';
}

/**
 * First name plus last initial: ("Priya", "Sharma") -> "Priya S.". The profile
 * stores the two separately (`UserProfile.firstName` / `lastName`), so nothing
 * is split here. First name only when the last name is blank. The initial is
 * the first grapheme, not `string[0]`, so Tamil (and other combining-mark
 * scripts) are not split.
 */
export function toDisplayName(
  firstName: string,
  lastName?: string | null,
): string {
  const first = firstName.trim();
  const last = (lastName ?? '').trim();
  if (!last) return first;
  return `${first} ${firstGrapheme(last).toLocaleUpperCase()}.`;
}

/** Internal -> public commission status. Unknown values fail safe to ON_HOLD. */
export function toPublicCommissionStatus(
  status: InternalCommissionStatus | null | undefined,
): PublicCommissionStatus | null {
  if (status == null) return null;
  return COMMISSION_STATUS_PUBLIC_MAP[status] ?? 'ON_HOLD';
}

/** Indian Standard Time: a fixed UTC+05:30 offset (India has no DST). */
export const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;

/** Date-only, YYYY-MM-DD, as the calendar date in Indian time. */
function toDateOnly(value: Date | string): string {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new RangeError('Invalid date.');
  }
  return new Date(date.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
}

function clampPct(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.min(100, Math.max(0, Math.round(value)));
}

export function toAgentReferralView(
  source: ReferralViewSource,
): AgentReferralView {
  return {
    id: source.attributionId,
    displayName: toDisplayName(source.firstName, source.lastName),
    age: source.age,
    city: source.city,
    signedUpAt: toDateOnly(source.signedUpAt),
    stage: source.stage,
    profileCompletenessPct: clampPct(source.profileCompletenessPct),
    planName: source.planName ?? null,
    purchasedAt:
      source.purchasedAt == null ? null : toDateOnly(source.purchasedAt),
    commissionStatus: toPublicCommissionStatus(source.commissionStatus),
    maskedPhone: maskPhone(source.phoneE164),
  };
}
