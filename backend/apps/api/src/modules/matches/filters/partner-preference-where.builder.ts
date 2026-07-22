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

// UI convenience tokens that mean "no preference" — they are not literal
// profile values, so they must never become a filter (doing so would exclude
// every real profile). Compared case-insensitively.
const MEANINGLESS_TOKENS: ReadonlySet<string> = new Set([
  'any',
  'any caste',
  'any degree',
  'any religion',
  'any mother tongue',
  'any city',
  'any state',
  "doesn't matter",
  'doesnt matter',
  'no preference',
  'inter-caste ok',
  'anywhere in india',
  'nri ok',
]);

export interface FeedWhereParams {
  currentUserId: string;
  /** The caller's own gender, if they've finalized a profile (opposite-gender
   *  matching is a matrimony default). Null → no gender constraint. */
  myGender: Gender | null;
  /** The caller's own matchable attributes, used to resolve relative "Same X"
   *  preferences (e.g. "Same Caste" → the caller's caste). Missing values make
   *  the corresponding "Same X" preference a no-op rather than an error. */
  self?: SelfAttributes | null;
  /** The caller's saved partner preference, or null if none set yet. */
  pref: PreferenceFilters | null;
}

/** The caller's own profile values a "Same X" preference resolves against. */
export interface SelfAttributes {
  caste?: string | null;
  currentCity?: string | null;
  currentState?: string | null;
  motherTongue?: string | null;
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
  /** Free-form advanced preferences (diet/smoking/drinking/country/…) captured
   *  by the standalone Partner Preferences page, stored as-is in the
   *  partner_preferences.extended_preferences JSON column. */
  extendedPreferences?: unknown;
}

/**
 * Pure, deterministic translation of a user's PartnerPreference into a Prisma
 * `UserProfile` WHERE clause. No scoring, no ranking — filtering only.
 *
 * Rules:
 *  - An empty / unset preference is IGNORED — never a reason to exclude.
 *  - "Any …" / "Doesn't Matter" / "Inter-Caste OK" / "Anywhere in India" and
 *    grouped UI labels (values with `/` or `+`, e.g. "Software / IT",
 *    "B.E / B.Tech+") are non-literal — they are dropped, never filtered on, so
 *    the feed never over-filters to an empty result on a non-literal choice.
 *  - "Same X" resolves to the caller's own attribute (caste/city/state/tongue).
 *  - Always excludes: the caller themselves, soft-deleted users, suspended/
 *    deactivated/banned users, incomplete profiles, and anyone with a mutual
 *    block against the caller. PENDING_VERIFICATION users ARE included — no
 *    verification flow exists yet to ever clear that state.
 *  - Only fields that exist on the schema are used; nothing is invented.
 */
export function buildFeedWhere(
  params: FeedWhereParams,
): Prisma.UserProfileWhereInput {
  const { currentUserId, myGender, self, pref } = params;

  const and: Prisma.UserProfileWhereInput[] = [
    { userId: { not: currentUserId } },
    // Defensive: a UserProfile row only exists once registration is finalized
    // (finalize() sets this true), but this guards against ever surfacing a
    // partially-written row.
    { isProfileComplete: true },
    {
      user: {
        is: {
          deletedAt: null,
          // Excludes only genuinely-bad account states (suspended, deactivated,
          // banned). PENDING_VERIFICATION is deliberately NOT excluded: there is
          // no verification flow in this app yet that ever promotes a user to
          // ACTIVE, so requiring ACTIVE would permanently hide every real
          // signup from Discover. Revisit this once verification exists.
          status: { notIn: ['SUSPENDED', 'DEACTIVATED', 'BANNED'] },
          // Mutual block: neither side of a block should see the other.
          NOT: [
            { blocksMade: { some: { blockedUserId: currentUserId } } },
            { blocksReceived: { some: { blockerId: currentUserId } } },
          ],
        },
      },
    },
  ];

  if (myGender === 'MALE') and.push({ gender: 'FEMALE' });
  else if (myGender === 'FEMALE') and.push({ gender: 'MALE' });
  else {
    // The opposite-gender rule is mandatory and must always apply — but with
    // no finalized profile, the caller's own gender (and therefore who counts
    // as "opposite") is unknown. Fail closed (zero results) rather than
    // silently returning an unfiltered, mixed-gender feed.
    and.push({ gender: { in: [] } });
  }

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

    addValues(and, 'religion', resolveValues(pref.preferredReligions));
    addValues(and, 'caste', resolveValues(pref.preferredCastes, self?.caste));
    addValues(
      and,
      'motherTongue',
      resolveValues(pref.preferredMotherTongues, self?.motherTongue),
    );
    addValues(and, 'highestEducation', resolveValues(pref.preferredEducation));
    addValues(and, 'profession', resolveValues(pref.preferredOccupations));

    // Location: the wizard stores a single meta-choice in preferredCities
    // ("Same City" | "Same State" | "Anywhere in India" | "NRI OK" | "Any", or
    // a literal city), so "Same State" must be routed to the state column, not
    // the city column. preferredStates is honored too (usually empty).
    const cityValues: string[] = [];
    const stateValues: string[] = [];
    for (const token of toStringArray(pref.preferredCities)) {
      const lower = token.toLowerCase();
      if (lower === 'same city') pushIf(cityValues, self?.currentCity);
      else if (lower === 'same state') pushIf(stateValues, self?.currentState);
      else if (isLiteral(token)) cityValues.push(token);
    }
    for (const value of resolveValues(pref.preferredStates, self?.currentState)) {
      stateValues.push(value);
    }
    addValues(and, 'currentCity', cityValues);
    addValues(and, 'currentState', stateValues);

    const maritalStatuses = toStringArray(pref.maritalStatusPref)
      .map((s) => s.toUpperCase().replace(/[\s-]+/g, '_'))
      .filter((s) => MARITAL_STATUSES.includes(s)) as MaritalStatus[];
    if (maritalStatuses.length > 0) {
      and.push({ maritalStatus: { in: maritalStatuses } });
    }

    const minIncome = toNumber(pref.minIncomeLakhs);
    if (minIncome !== null && minIncome > 0) {
      and.push({ annualIncomeLakhs: { gte: minIncome } });
    }

    // Advanced lifestyle/location preferences from the standalone Partner
    // Preferences page (partner_preferences.extended_preferences JSON). Applied
    // only when a literal value is present — same "ignore Any/meta" rule.
    const ext = asRecord(pref.extendedPreferences);
    addEquals(and, 'dietaryHabits', ext.diet);
    addEquals(and, 'smokingHabits', ext.smoking);
    addEquals(and, 'drinkingHabits', ext.drinking);
    addEquals(and, 'country', ext.country);
    // "Ethnicity" in the standalone Partner Preferences page's Religion &
    // Community section is a community name (Vellalar/Nadar/Iyer/…) — maps to
    // UserProfile.community, distinct from the base castePref -> caste filter.
    addEquals(and, 'community', ext.ethnicity);
    addEquals(and, 'subCaste', ext.subCaste);
  }

  return { AND: and };
}

/**
 * Resolves raw preference tokens into concrete, matchable profile values:
 *  - "Same X" → the caller's own attribute (dropped if the caller has none),
 *  - a literal value → kept,
 *  - "Any"/meta/grouped label → dropped.
 * De-duplicated, order-preserving.
 */
function resolveValues(raw: unknown, ownValue?: string | null): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const token of toStringArray(raw)) {
    let value: string | null = null;
    if (isSame(token)) {
      value = hasText(ownValue) ? ownValue.trim() : null;
    } else if (isLiteral(token)) {
      value = token;
    }
    if (value !== null && !seen.has(value)) {
      seen.add(value);
      out.push(value);
    }
  }
  return out;
}

// Case-insensitive membership: real profile data has inconsistent casing
// (e.g. "sheikh" vs "Sheikh"), so an exact `in` would silently miss and return
// an empty feed. Expressed as an OR of case-insensitive equals on one field.
function addValues(
  and: Prisma.UserProfileWhereInput[],
  field: keyof Prisma.UserProfileWhereInput,
  values: string[],
): void {
  const unique = Array.from(new Set(values.map((v) => v.trim()))).filter(
    (v) => v.length > 0,
  );
  if (unique.length === 0) return;
  and.push({
    OR: unique.map((v) => insensitiveEquals(field, v)),
  });
}

function addEquals(
  and: Prisma.UserProfileWhereInput[],
  field: keyof Prisma.UserProfileWhereInput,
  value: unknown,
): void {
  if (typeof value !== 'string') return;
  const trimmed = value.trim();
  if (!isLiteral(trimmed)) return;
  and.push(insensitiveEquals(field, trimmed));
}

function insensitiveEquals(
  field: keyof Prisma.UserProfileWhereInput,
  value: string,
): Prisma.UserProfileWhereInput {
  return {
    [field]: { equals: value, mode: 'insensitive' },
  } as Prisma.UserProfileWhereInput;
}

/** A stored value is a literal, matchable profile value only if it is non-empty,
 *  not an "Any"/meta token, and not a grouped UI label (`/` or `+`). */
function isLiteral(token: string): boolean {
  const t = token.trim();
  if (t.length === 0) return false;
  if (MEANINGLESS_TOKENS.has(t.toLowerCase())) return false;
  if (t.includes('/') || t.includes('+')) return false;
  return true;
}

function isSame(token: string): boolean {
  return token.trim().toLowerCase().startsWith('same ');
}

function pushIf(arr: string[], value?: string | null): void {
  if (hasText(value)) arr.push(value.trim());
}

function hasText(value?: string | null): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
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
  return new Date(date.getFullYear() - years, date.getMonth(), date.getDate());
}

function addDays(date: Date, days: number): Date {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}
