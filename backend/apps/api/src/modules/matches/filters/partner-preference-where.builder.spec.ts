import {
  buildFeedWhere,
  FeedWhereParams,
} from './partner-preference-where.builder';
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
  return {
    [field]: { equals: value, mode: 'insensitive' },
  } as Prisma.UserProfileWhereInput;
}
function hasCiIn(
  params: FeedWhereParams,
  field: string,
  values: string[],
): boolean {
  const want = JSON.stringify({ OR: values.map((v) => ci(field, v)) });
  return clauses(params).some((c) => JSON.stringify(c) === want);
}

// A known gender by default, so every other test's clause count is isolated
// from the "unknown own gender" edge case (covered by its own dedicated test
// below) rather than tripping over it incidentally.
const base: FeedWhereParams = {
  currentUserId: 'me',
  myGender: 'MALE',
  self: null,
  pref: null,
};

const BASE_CLAUSE_COUNT = 4; // self-exclusion, isProfileComplete, user.is{...}, gender

describe('buildFeedWhere', () => {
  it('always excludes the caller, incomplete profiles, and invalid users', () => {
    const c = clauses(base);
    expect(c).toContainEqual({ userId: { not: 'me' } });
    expect(c).toContainEqual({ isProfileComplete: true });
    expect(
      c.some(
        (x) =>
          'user' in x &&
          JSON.stringify(x) ===
            JSON.stringify({
              user: {
                is: {
                  deletedAt: null,
                  status: { notIn: ['SUSPENDED', 'DEACTIVATED', 'BANNED'] },
                  NOT: [
                    { blocksMade: { some: { blockedUserId: 'me' } } },
                    { blocksReceived: { some: { blockerId: 'me' } } },
                    // F5: declined interests are hard eligibility on every
                    // surface, not only from fallback Tier 2 onward.
                    {
                      receivedInterests: {
                        some: { senderId: 'me', status: 'DECLINED' },
                      },
                    },
                    {
                      sentInterests: {
                        some: { receiverId: 'me', status: 'DECLINED' },
                      },
                    },
                  ],
                },
              },
            }),
      ),
    ).toBe(true);
  });

  it('applies opposite-gender matching when gender is known', () => {
    expect(
      has(
        { ...base, myGender: 'MALE' },
        (c) => 'gender' in c && c.gender === 'FEMALE',
      ),
    ).toBe(true);
    expect(
      has(
        { ...base, myGender: 'FEMALE' },
        (c) => 'gender' in c && c.gender === 'MALE',
      ),
    ).toBe(true);
    expect(clauses(base)).toHaveLength(BASE_CLAUSE_COUNT);
  });

  it("fails closed (zero possible results) when the caller's own gender is unknown", () => {
    // No finalized profile → myGender is null. The exclusivity rule is
    // mandatory, so with no self-gender to anchor "opposite", it must never
    // fall back to "no constraint" (which would leak a mixed-gender feed).
    const c = clauses({ ...base, myGender: null });
    expect(c).toContainEqual({ gender: { in: [] } });
    expect(c).toHaveLength(BASE_CLAUSE_COUNT);
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
    // Only the base clauses survive.
    expect(c).toHaveLength(BASE_CLAUSE_COUNT);
  });

  it('applies literal values as case-insensitive filters', () => {
    expect(
      hasCiIn(
        { ...base, pref: { preferredReligions: ['Hindu', 'Jain'] } },
        'religion',
        ['Hindu', 'Jain'],
      ),
    ).toBe(true);
  });

  it('resolves "Same Caste" to the caller\'s own caste', () => {
    expect(
      hasCiIn(
        {
          ...base,
          self: { caste: 'Iyer' },
          pref: { preferredCastes: ['Same Caste'] },
        },
        'caste',
        ['Iyer'],
      ),
    ).toBe(true);
    // No own caste → "Same Caste" becomes a no-op (base clauses only).
    expect(
      clauses({ ...base, pref: { preferredCastes: ['Same Caste'] } }),
    ).toHaveLength(BASE_CLAUSE_COUNT);
  });

  it('routes "Same City" / "Same State" to the correct columns', () => {
    const self = { currentCity: 'Chennai', currentState: 'Tamil Nadu' };
    expect(
      hasCiIn(
        { ...base, self, pref: { preferredCities: ['Same City'] } },
        'currentCity',
        ['Chennai'],
      ),
    ).toBe(true);
    expect(
      hasCiIn(
        { ...base, self, pref: { preferredCities: ['Same State'] } },
        'currentState',
        ['Tamil Nadu'],
      ),
    ).toBe(true);
  });

  it('drops grouped UI labels (with "/" or "+") that never match a profile', () => {
    // Labels that are neither a mapped category nor a real profile value.
    // Known categories ("Software / IT", "B.E / B.Tech+") are expanded
    // instead — see preference-categories.spec.ts.
    expect(
      clauses({
        ...base,
        pref: {
          preferredOccupations: ['Arts / Media'],
          preferredEducation: ['Diploma+'],
        },
      }),
    ).toHaveLength(BASE_CLAUSE_COUNT);
  });

  it('normalizes marital-status labels to enum values', () => {
    expect(
      has(
        { ...base, pref: { maritalStatusPref: ['Never Married'] } },
        (c) =>
          JSON.stringify(c) ===
          JSON.stringify({ maritalStatus: { in: ['NEVER_MARRIED'] } }),
      ),
    ).toBe(true);
    // "Doesn't Matter" / "Any" are not valid enum values → dropped.
    expect(
      clauses({
        ...base,
        pref: { maritalStatusPref: ["Doesn't Matter", 'Any'] },
      }),
    ).toHaveLength(BASE_CLAUSE_COUNT);
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
    expect(c).toContainEqual({
      dietaryHabits: { equals: 'Vegetarian', mode: 'insensitive' },
    });
    expect(c).toContainEqual({
      smokingHabits: { equals: 'No', mode: 'insensitive' },
    });
    expect(c).toContainEqual({
      country: { equals: 'India', mode: 'insensitive' },
    });
    expect(c.some((x) => 'drinkingHabits' in x)).toBe(false);
  });

  it('applies extended community (ethnicity) and sub-caste preferences', () => {
    const c = clauses({
      ...base,
      pref: { extendedPreferences: { ethnicity: 'Iyer', subCaste: 'Vadama' } },
    });
    expect(c).toContainEqual({
      community: { equals: 'Iyer', mode: 'insensitive' },
    });
    expect(c).toContainEqual({
      subCaste: { equals: 'Vadama', mode: 'insensitive' },
    });
  });

  it('excludes suspended/deactivated/banned users but not PENDING_VERIFICATION, and excludes both directions of a block and of a declined interest', () => {
    const c = clauses({ ...base, currentUserId: 'user-42' });
    const userClause = c.find((x) => 'user' in x) as {
      user: { is: Record<string, unknown> };
    };
    expect(userClause.user.is.status).toEqual({
      notIn: ['SUSPENDED', 'DEACTIVATED', 'BANNED'],
    });
    expect(userClause.user.is.NOT).toEqual([
      { blocksMade: { some: { blockedUserId: 'user-42' } } },
      { blocksReceived: { some: { blockerId: 'user-42' } } },
      {
        receivedInterests: {
          some: { senderId: 'user-42', status: 'DECLINED' },
        },
      },
      {
        sentInterests: {
          some: { receiverId: 'user-42', status: 'DECLINED' },
        },
      },
    ]);
  });

  it('applies age and height bounds', () => {
    const c = clauses({
      ...base,
      pref: { minAge: 25, maxAge: 30, minHeightCm: 150, maxHeightCm: 175 },
    });
    expect(c.some((x) => 'dob' in x)).toBe(true);
    expect(c).toContainEqual({ heightCm: { gte: 150 } });
    expect(c).toContainEqual({ heightCm: { lte: 175 } });
  });
});
