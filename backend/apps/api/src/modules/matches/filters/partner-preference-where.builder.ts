import type {
  Prisma,
  Gender,
  MaritalStatus,
} from '../../../../../../libs/database/generated/client';

const MARITAL_STATUSES: readonly string[] = [
  'NEVER_MARRIED',
  'DIVORCED',
  'WIDOWED',
  'AWAITING_DIVORCE',
];

export interface FeedWhereParams {
  currentUserId: string;
  /** The caller's own gender, if they've finalized a profile (opposite-gender
   *  matching is a matrimony default). Null → no gender constraint. */
  myGender: Gender | null;
  /** The caller's saved partner preference, or null if none set yet. */
  pref: PreferenceFilters | null;
}

/** Only the preference fields the schema actually stores (partner_preferences). */
export interface PreferenceFilters {
  minAge?: number | null;
  maxAge?: number | null;
  minHeightCm?: number | null;
  maxHeightCm?: number | null;
  preferredReligions?: unknown;
  preferredCastes?: unknown;
  preferredMotherTongues?: unknown;
  preferredEducation?: unknown;
  preferredOccupations?: unknown;
  preferredCities?: unknown;
  preferredStates?: unknown;
  maritalStatusPref?: unknown;
  minIncomeLakhs?: unknown;
}

/**
 * Pure, deterministic translation of a user's PartnerPreference into a Prisma
 * `UserProfile` WHERE clause. No scoring, no ranking — filtering only.
 *
 * Rules (per Phase 2 spec):
 *  - An empty / unset preference is IGNORED — never a reason to exclude.
 *  - Always excludes the caller themselves and soft-deleted (inactive) users.
 *  - Only fields that exist on the schema are used; nothing is invented.
 */
export function buildFeedWhere(
  params: FeedWhereParams,
): Prisma.UserProfileWhereInput {
  const { currentUserId, myGender, pref } = params;

  const and: Prisma.UserProfileWhereInput[] = [
    { userId: { not: currentUserId } },
    // "Inactive" = soft-deleted account. (A UserProfile row only exists once
    // registration is finalized, so incomplete profiles are already excluded.)
    { user: { is: { deletedAt: null } } },
  ];

  if (myGender === 'MALE') and.push({ gender: 'FEMALE' });
  else if (myGender === 'FEMALE') and.push({ gender: 'MALE' });

  if (pref) {
    // Date-only "today" so the bounds are birthday-accurate and immune to the
    // time-of-day component of a stored DOB (which otherwise causes off-by-one
    // at exact age boundaries).
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    // minAge = youngest allowed: born on or before (today - minAge years) —
    // include the whole of that birthday, hence `< nextDay`.
    if (isPositive(pref.minAge)) {
      and.push({
        dob: { lt: addDays(subtractYears(today, pref.minAge as number), 1) },
      });
    }
    // maxAge = oldest allowed: anyone who turns (maxAge + 1) on/before today is
    // excluded, so dob must be on/after the day after (today - (maxAge+1) yrs).
    if (isPositive(pref.maxAge)) {
      and.push({
        dob: {
          gte: addDays(subtractYears(today, (pref.maxAge as number) + 1), 1),
        },
      });
    }
    if (isPositive(pref.minHeightCm)) {
      and.push({ heightCm: { gte: pref.minHeightCm as number } });
    }
    if (isPositive(pref.maxHeightCm)) {
      and.push({ heightCm: { lte: pref.maxHeightCm as number } });
    }

    addIn(and, 'religion', pref.preferredReligions);
    addIn(and, 'caste', pref.preferredCastes);
    addIn(and, 'motherTongue', pref.preferredMotherTongues);
    addIn(and, 'highestEducation', pref.preferredEducation);
    addIn(and, 'profession', pref.preferredOccupations);
    addIn(and, 'currentCity', pref.preferredCities);
    addIn(and, 'currentState', pref.preferredStates);

    const maritalStatuses = toStringArray(pref.maritalStatusPref).filter((s) =>
      MARITAL_STATUSES.includes(s),
    ) as MaritalStatus[];
    if (maritalStatuses.length > 0) {
      and.push({ maritalStatus: { in: maritalStatuses } });
    }

    const minIncome = toNumber(pref.minIncomeLakhs);
    if (minIncome !== null && minIncome > 0) {
      and.push({ annualIncomeLakhs: { gte: minIncome } });
    }
  }

  return { AND: and };
}

function addIn(
  and: Prisma.UserProfileWhereInput[],
  field: keyof Prisma.UserProfileWhereInput,
  value: unknown,
): void {
  const values = toStringArray(value);
  if (values.length > 0) {
    and.push({ [field]: { in: values } } as Prisma.UserProfileWhereInput);
  }
}

function toStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((v) => (typeof v === 'string' ? v.trim() : ''))
    .filter((v) => v.length > 0);
}

function toNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function isPositive(value: unknown): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
}

function subtractYears(date: Date, years: number): Date {
  return new Date(
    date.getFullYear() - years,
    date.getMonth(),
    date.getDate(),
  );
}

function addDays(date: Date, days: number): Date {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}
