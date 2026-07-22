import { buildFeedWhere, FeedWhereParams } from './partner-preference-where.builder';
import type { Prisma } from '../../../../../../libs/database/generated/client';

// Pulls the AND clauses out for assertion. buildFeedWhere always returns
// `{ AND: [...] }`, so this is safe.
function clauses(params: FeedWhereParams): Prisma.UserProfileWhereInput[] {
  return (buildFeedWhere(params).AND as Prisma.UserProfileWhereInput[]) ?? [];
}

function has(
  params: FeedWhereParams,
  predicate: (c: Prisma.UserProfileWhereInput) => boolean,
): boolean {
  return clauses(params).some(predicate);
}

// String matching is emitted as an OR of case-insensitive equals on one field.
function ci(field: string, value: string): Prisma.UserProfileWhereInput {
  return { [field]: { equals: value, mode: 'insensitive' } } as Prisma.UserProfileWhereInput;
}
function hasCiIn(
  params: FeedWhereParams,
  field: string,
  values: string[],
): boolean {
  const want = JSON.stringify({ OR: values.map((v) => ci(field, v)) });
  return clauses(params).some((c) => JSON.stringify(c) === want);
}

const base: FeedWhereParams = {
  currentUserId: 'me',
  myGender: null,
  self: null,
  pref: null,
};

describe('buildFeedWhere', () => {
  it('always excludes the caller and soft-deleted users', () => {
    const c = clauses(base);
    expect(c).toContainEqual({ userId: { not: 'me' } });
    expect(c).toContainEqual({ user: { is: { deletedAt: null } } });
  });

  it('applies opposite-gender matching when gender is known', () => {
    expect(has({ ...base, myGender: 'MALE' }, (c) => 'gender' in c && c.gender === 'FEMALE')).toBe(true);
    expect(has({ ...base, myGender: 'FEMALE' }, (c) => 'gender' in c && c.gender === 'MALE')).toBe(true);
    // Unknown gender → no gender constraint (only the two base clauses).
    expect(clauses(base)).toHaveLength(2);
  });

  it('ignores empty / "Any" / meta preference tokens (never over-filters)', () => {
    const c = clauses({
      ...base,
      pref: {
        preferredReligions: ['Any'],
        preferredCastes: ['Any Caste', 'Inter-Caste OK'],
        preferredCities: ['Anywhere in India'],
        preferredMotherTongues: [],
      },
    });
    // Only the two base clauses survive.
    expect(c).toHaveLength(2);
  });

  it('applies literal values as case-insensitive filters', () => {
    expect(hasCiIn({ ...base, pref: { preferredReligions: ['Hindu', 'Jain'] } }, 'religion', ['Hindu', 'Jain'])).toBe(true);
  });

  it('resolves "Same Caste" to the caller\'s own caste', () => {
    expect(
      hasCiIn({ ...base, self: { caste: 'Iyer' }, pref: { preferredCastes: ['Same Caste'] } }, 'caste', ['Iyer']),
    ).toBe(true);
    // No own caste → "Same Caste" becomes a no-op (2 base clauses only).
    expect(clauses({ ...base, pref: { preferredCastes: ['Same Caste'] } })).toHaveLength(2);
  });

  it('routes "Same City" / "Same State" to the correct columns', () => {
    const self = { currentCity: 'Chennai', currentState: 'Tamil Nadu' };
    expect(hasCiIn({ ...base, self, pref: { preferredCities: ['Same City'] } }, 'currentCity', ['Chennai'])).toBe(true);
    expect(hasCiIn({ ...base, self, pref: { preferredCities: ['Same State'] } }, 'currentState', ['Tamil Nadu'])).toBe(true);
  });

  it('drops grouped UI labels (with "/" or "+") that never match a profile', () => {
    expect(
      clauses({
        ...base,
        pref: {
          preferredOccupations: ['Software / IT'],
          preferredEducation: ['B.E / B.Tech+'],
        },
      }),
    ).toHaveLength(2);
  });

  it('normalizes marital-status labels to enum values', () => {
    expect(
      has({ ...base, pref: { maritalStatusPref: ['Never Married'] } }, (c) =>
        JSON.stringify(c) === JSON.stringify({ maritalStatus: { in: ['NEVER_MARRIED'] } }),
      ),
    ).toBe(true);
    // "Doesn't Matter" / "Any" are not valid enum values → dropped.
    expect(clauses({ ...base, pref: { maritalStatusPref: ["Doesn't Matter", 'Any'] } })).toHaveLength(2);
  });

  it('applies extended lifestyle preferences (diet/smoking/drinking/country)', () => {
    const c = clauses({
      ...base,
      pref: {
        extendedPreferences: {
          diet: 'Vegetarian',
          smoking: 'No',
          country: 'India',
          drinking: 'Any', // meta → ignored
        },
      },
    });
    expect(c).toContainEqual({ dietaryHabits: { equals: 'Vegetarian', mode: 'insensitive' } });
    expect(c).toContainEqual({ smokingHabits: { equals: 'No', mode: 'insensitive' } });
    expect(c).toContainEqual({ country: { equals: 'India', mode: 'insensitive' } });
    expect(c.some((x) => 'drinkingHabits' in x)).toBe(false);
  });

  it('applies age and height bounds', () => {
    const c = clauses({ ...base, pref: { minAge: 25, maxAge: 30, minHeightCm: 150, maxHeightCm: 175 } });
    expect(c.some((x) => 'dob' in x)).toBe(true);
    expect(c).toContainEqual({ heightCm: { gte: 150 } });
    expect(c).toContainEqual({ heightCm: { lte: 175 } });
  });
});
