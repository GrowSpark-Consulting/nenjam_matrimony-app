import { CompatibilityService } from '../scoring/compatibility.service';
import type {
  CompatibilityBreakdown,
  ScorableProfile,
} from '../scoring/compatibility.service';
import { RankingService } from '../scoring/ranking.service';
import type { RankingStrategy } from '../scoring/ranking.service';
import { toScorable } from '../scoring/scorable.mapper';
import type { PreferenceFilters } from '../filters/partner-preference-where.builder';
import type { FeedProfileRow } from '../repositories/feed.repository';

/**
 * Golden master for the compatibility score and the ranking built on it.
 *
 * The snapshot beside this file was recorded against the scoring code BEFORE
 * it was split into signals, and is the contract that split must honour: every
 * seeker/candidate pair below has to produce the same seeker fit, mutual fit,
 * overall score, band and per-component breakdown, and every ranking the same
 * order. A diff here is a change to matching behaviour, not a stale snapshot —
 * find the cause rather than updating it.
 *
 * Deliberately includes the cases the audit flagged as scoring bugs, recorded
 * as they behave so that fixing one is a visible, reviewed change to this file.
 * Marital labels ("Never Married" vs NEVER_MARRIED) and "Same State" (scored
 * against the seeker's city) were fixed that way — the `onboarding-labels`
 * snapshot changed, and nothing else did. Grouped education labels
 * ("B.E / B.Tech+") are still recorded as unmatched.
 *
 * Only the fields that existed before the refactor are recorded, so fields
 * added to the breakdown later cannot move this baseline.
 */

// A fixed clock: age and activity both read Date.now().
const NOW = new Date('2026-06-15T12:00:00.000Z');
const DAY = 86_400_000;
const utc = (iso: string): Date => new Date(`${iso}T00:00:00.000Z`);

interface CandidateSpec {
  userId: string;
  row: Record<string, unknown>;
  trustScore?: number;
  preference?: PreferenceFilters | null;
}

/** A feed row shaped exactly as FEED_PROFILE_SELECT returns it. */
function feedRow(spec: CandidateSpec): FeedProfileRow {
  return {
    userId: spec.userId,
    dob: utc('1998-03-10'),
    gender: 'FEMALE',
    heightCm: 163,
    religion: 'Hindu',
    caste: 'Iyer',
    community: 'Brahmin',
    motherTongue: 'Tamil',
    highestEducation: 'B.E',
    profession: 'Software Engineer',
    currentCity: 'Chennai',
    currentState: 'Tamil Nadu',
    maritalStatus: 'NEVER_MARRIED',
    dietaryHabits: 'Vegetarian',
    smokingHabits: 'No',
    drinkingHabits: 'No',
    profileCompletePct: 80,
    updatedAt: new Date(NOW.getTime() - 3 * DAY),
    createdAt: new Date(NOW.getTime() - 30 * DAY),
    ...spec.row,
    user: {
      phone: '+910000000000',
      trustScore: spec.trustScore ?? 40,
      partnerPreference: spec.preference ?? null,
      photos: [],
    },
  };
}

const SEEKER: ScorableProfile = {
  userId: 'seeker',
  dob: utc('1995-07-01'),
  heightCm: 175,
  religion: 'Hindu',
  caste: 'Iyer',
  community: 'Brahmin',
  motherTongue: 'Tamil',
  highestEducation: 'M.Tech',
  profession: 'Architect',
  currentCity: 'Chennai',
  currentState: 'Tamil Nadu',
  maritalStatus: 'NEVER_MARRIED',
  dietaryHabits: 'Vegetarian',
  smokingHabits: 'No',
  drinkingHabits: 'No',
  profileCompletePct: 90,
  // The seeker row never carries a trust score (findSelf does not select one).
  trustScore: null,
  updatedAt: new Date(NOW.getTime() - 1 * DAY),
  preference: null,
};

/** A fully stated preference, as PUT /discover/preferences stores it. */
const FULL_PREF: PreferenceFilters = {
  minAge: 25,
  maxAge: 30,
  minHeightCm: 155,
  maxHeightCm: 170,
  preferredReligions: ['Hindu'],
  preferredCastes: ['Same Caste'],
  preferredMotherTongues: ['Same Mother Tongue'],
  preferredEducation: ['B.E'],
  preferredOccupations: ['Software Engineer'],
  preferredCities: ['Chennai'],
  preferredStates: [],
  maritalStatusPref: ['NEVER_MARRIED'],
  minIncomeLakhs: '5',
  extendedPreferences: { diet: 'Vegetarian', smoking: 'No', drinking: 'No' },
};

/** What the onboarding picker actually writes — labels, not enum values. */
const LABEL_PREF: PreferenceFilters = {
  minAge: 22,
  maxAge: 35,
  minHeightCm: 140,
  maxHeightCm: 210,
  preferredReligions: ['Hindu'],
  preferredCastes: ['Any Caste'],
  preferredMotherTongues: ['Tamil'],
  preferredEducation: ['B.E / B.Tech+'],
  preferredOccupations: ['Software / IT'],
  preferredCities: ['Same State'],
  preferredStates: [],
  maritalStatusPref: ['Never Married'],
  minIncomeLakhs: null,
  extendedPreferences: {},
};

/** A candidate's own preference that the seeker satisfies. */
const LIKES_SEEKER: PreferenceFilters = {
  minAge: 28,
  maxAge: 34,
  minHeightCm: 170,
  maxHeightCm: 185,
  preferredReligions: ['Hindu'],
  preferredCastes: ['Same Caste'],
  preferredCities: ['Same City'],
  maritalStatusPref: ['NEVER_MARRIED'],
};

/** A candidate's own preference that the seeker fails on most counts. */
const REJECTS_SEEKER: PreferenceFilters = {
  minAge: 22,
  maxAge: 26,
  minHeightCm: 180,
  maxHeightCm: 195,
  preferredReligions: ['Christian'],
  preferredMotherTongues: ['Malayalam'],
  preferredCities: ['Kochi'],
  extendedPreferences: { diet: 'Non-Vegetarian' },
};

// Twelve candidates, each isolating one behaviour the score depends on.
const CANDIDATES: CandidateSpec[] = [
  { userId: 'c01-exact', row: {} },
  { userId: 'c02-wrong-religion', row: { religion: 'Christian', caste: null, community: null } },
  { userId: 'c03-caste-via-community', row: { caste: 'Vadama', community: 'Iyer' } },
  { userId: 'c04-age-2y-over', row: { dob: utc('1993-09-01') } },
  { userId: 'c05-no-dob-no-height', row: { dob: null, heightCm: null } },
  { userId: 'c06-height-4cm-over', row: { heightCm: 174 } },
  { userId: 'c07-same-state-other-city', row: { currentCity: 'Madurai' } },
  { userId: 'c08-other-state', row: { currentCity: 'Bengaluru', currentState: 'Karnataka' } },
  { userId: 'c09-lifestyle-partial', row: { dietaryHabits: 'Non-Vegetarian', smokingHabits: 'No', drinkingHabits: 'Occasionally' } },
  { userId: 'c10-likes-seeker', row: {}, preference: LIKES_SEEKER, trustScore: 90 },
  { userId: 'c11-rejects-seeker', row: {}, preference: REJECTS_SEEKER, trustScore: 90 },
  {
    userId: 'c12-stale-low-quality',
    row: {
      profileCompletePct: 20,
      updatedAt: new Date(NOW.getTime() - 60 * DAY),
      createdAt: new Date(NOW.getTime() - 400 * DAY),
      maritalStatus: 'DIVORCED',
      highestEducation: 'MBA',
      profession: 'Teacher',
    },
    trustScore: 0,
  },
];

// Two candidates share an identical profile and creation time, so their order
// is decided by the final userId tie-break alone.
const TIE_ROWS: CandidateSpec[] = [
  { userId: 'tie-b', row: { createdAt: new Date(NOW.getTime() - 10 * DAY) } },
  { userId: 'tie-a', row: { createdAt: new Date(NOW.getTime() - 10 * DAY) } },
];

const SEEKER_PREFS: Array<[string, PreferenceFilters | null]> = [
  ['full-preference', FULL_PREF],
  ['onboarding-labels', LABEL_PREF],
  ['no-preference', null],
];

/** The pre-refactor fields of a breakdown, and nothing else. */
function record(b: CompatibilityBreakdown | undefined) {
  if (!b) return null;
  return {
    seekerFit: b.seekerFit,
    mutualFit: b.mutualFit,
    overall: b.overall,
    band: b.band,
    components: b.components.map((c) => ({
      key: c.key,
      ratio: c.ratio,
      weight: c.weight,
      points: c.points,
      applicable: c.applicable,
    })),
  };
}

describe('compatibility + ranking golden master', () => {
  const compatibility = new CompatibilityService();
  const ranking = new RankingService();
  const rows = [...CANDIDATES, ...TIE_ROWS].map(feedRow);

  beforeAll(() => {
    jest.useFakeTimers({ now: NOW });
  });
  afterAll(() => {
    jest.useRealTimers();
  });

  describe.each(SEEKER_PREFS)('seeker with %s', (_label, pref) => {
    const score = () =>
      compatibility.scoreMany(SEEKER, pref, rows.map((r) => toScorable(r)));

    it('scores every candidate exactly as before', () => {
      const scores = score();
      const out: Record<string, unknown> = {};
      for (const row of rows) {
        out[String(row.userId)] = record(scores.get(String(row.userId)));
      }
      expect(out).toMatchSnapshot();
    });

    it.each<RankingStrategy>(['compatibility', 'mutual', 'recency'])(
      'ranks the pool in the same order (%s)',
      (strategy) => {
        const scores = score();
        const candidates = rows.map((row) => ({
          row,
          score: scores.get(String(row.userId)),
        }));
        const order = (opts: Parameters<RankingService['rank']>[3]) =>
          ranking
            .rank(candidates, strategy, { skip: 0, take: 50 }, opts)
            .map((c) => String(c.row.userId));

        const full = order({});
        // Seen demotion and the cursor boundary are part of the ordering
        // contract the page depends on, so they are pinned too.
        const withSeen = order({ seen: new Set(['c01-exact', 'c10-likes-seeker']) });
        const afterFourth = ranking
          .rank(candidates, strategy, { skip: 0, take: 50 }, {
            cursor: ranking.cursorFor(
              candidates.find((c) => c.row.userId === full[3])!,
              strategy,
            ),
          })
          .map((c) => String(c.row.userId));

        expect({ full, withSeen, afterFourth }).toMatchSnapshot();
      },
    );
  });
});
