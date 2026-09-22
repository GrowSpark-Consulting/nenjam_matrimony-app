import {
  isLiteral,
  resolveLocation,
  resolveEducation,
  resolveMaritalStatuses,
  resolveOccupations,
  resolveValues,
  type PreferenceFilters,
  type SelfAttributes,
} from '../../filters/partner-preference-where.builder';
import {
  scoreComponent,
  type CompatibilityInput,
  type CompatibilitySignal,
  type ScorableProfile,
  type ScoreComponent,
} from '../compatibility-signal';
import type { ScoreKey } from '../matching-weights.config';

const MS_PER_DAY = 86_400_000;

/**
 * How well a candidate fits the partner preferences someone saved.
 *
 * Preference vocabulary is interpreted in exactly one place. `resolveValues`
 * and `isLiteral` are imported from the WHERE builder — the same functions the
 * filter uses. "Any Caste" is meaningless in both, "Same City" resolves to the
 * chooser's own city in both, and a grouped UI label like "Software / IT" is
 * non-literal in both. A second interpretation here would eventually disagree
 * with the filter, and a candidate would be filtered in but scored as a
 * mismatch.
 *
 * An unstated preference is not a failure: it comes back inapplicable and is
 * removed from the denominator, so a member who skipped half the form is
 * scored on what they did state rather than penalised for what they didn't.
 */
export const PREFERENCE_COMPATIBILITY_SIGNAL: CompatibilitySignal = {
  key: 'preference',
  kind: 'compatibility',
  keys: [
    'age',
    'religion',
    'community',
    'motherTongue',
    'location',
    'education',
    'profession',
    'maritalStatus',
    'height',
    'lifestyle',
  ],
  components({ chooser, preference: pref, candidate }: CompatibilityInput) {
    const self: SelfAttributes = {
      caste: chooser.caste,
      currentCity: chooser.currentCity,
      currentState: chooser.currentState,
      motherTongue: chooser.motherTongue,
    };

    return [
      ageComponent(pref, candidate),
      listComponent(
        'religion',
        pref?.preferredReligions,
        candidate.religion,
        null,
      ),
      communityComponent(pref, candidate, self),
      listComponent(
        'motherTongue',
        pref?.preferredMotherTongues,
        candidate.motherTongue,
        self.motherTongue ?? null,
      ),
      locationComponent(pref, candidate, self),
      categoryComponent(
        'education',
        resolveEducation(pref?.preferredEducation),
        candidate.highestEducation,
      ),
      categoryComponent(
        'profession',
        resolveOccupations(pref?.preferredOccupations),
        candidate.profession,
      ),
      maritalStatusComponent(pref, candidate),
      heightComponent(pref, candidate),
      lifestyleComponent(pref, candidate),
    ];
  },
};

/**
 * Inside the stated band scores 1. Outside it decays rather than dropping to
 * zero, because a candidate one year over a stated maximum is a far better
 * suggestion than one ten years over, and a cliff edge would rank them the
 * same.
 */
function ageComponent(
  pref: PreferenceFilters | null,
  candidate: ScorableProfile,
): ScoreComponent {
  const min = pref?.minAge ?? null;
  const max = pref?.maxAge ?? null;
  const age = ageOf(candidate.dob);
  if (age === null || (min === null && max === null)) {
    return scoreComponent('age', 0, false);
  }
  const lo = min ?? 0;
  const hi = max ?? 200;
  if (age >= lo && age <= hi) return scoreComponent('age', 1, true);
  const overshoot = age < lo ? lo - age : age - hi;
  // 5 years outside the band = no credit.
  return scoreComponent('age', 1 - overshoot / 5, true);
}

function heightComponent(
  pref: PreferenceFilters | null,
  candidate: ScorableProfile,
): ScoreComponent {
  const min = pref?.minHeightCm ?? null;
  const max = pref?.maxHeightCm ?? null;
  const h = candidate.heightCm;
  if (h === null || (min === null && max === null)) {
    return scoreComponent('height', 0, false);
  }
  const lo = min ?? 0;
  const hi = max ?? 300;
  if (h >= lo && h <= hi) return scoreComponent('height', 1, true);
  const overshoot = h < lo ? lo - h : h - hi;
  // 10 cm outside the band = no credit.
  return scoreComponent('height', 1 - overshoot / 10, true);
}

/**
 * Membership against a preference list, using the WHERE builder's own
 * resolution so "Any …" is ignored and "Same X" resolves identically.
 * An empty resolved list means nothing matchable was stated.
 */
function listComponent(
  key: ScoreKey,
  raw: unknown,
  candidateValue: string | null,
  ownValue: string | null,
): ScoreComponent {
  const wanted = resolveValues(raw, ownValue);
  if (wanted.length === 0 || !candidateValue) {
    return scoreComponent(key, 0, false);
  }
  const hit = wanted.some(
    (w) => w.trim().toLowerCase() === candidateValue.trim().toLowerCase(),
  );
  return scoreComponent(key, hit ? 1 : 0, true);
}

/**
 * Membership against an already-resolved list of profile values — education
 * and occupation, whose preference options are categories that the filter's
 * own resolvers expand ("B.E / B.Tech+" → B.E / B.Tech, M.Tech / M.E, Ph.D).
 * Resolving here the same way is what keeps a candidate the filter accepted
 * from scoring as a mismatch.
 */
function categoryComponent(
  key: ScoreKey,
  wanted: string[],
  candidateValue: string | null,
): ScoreComponent {
  if (wanted.length === 0 || !candidateValue) {
    return scoreComponent(key, 0, false);
  }
  const have = candidateValue.trim().toLowerCase();
  const hit = wanted.some((w) => w.trim().toLowerCase() === have);
  return scoreComponent(key, hit ? 1 : 0, true);
}

/** Caste preference, checked against caste then community. */
function communityComponent(
  pref: PreferenceFilters | null,
  candidate: ScorableProfile,
  self: SelfAttributes,
): ScoreComponent {
  const wanted = resolveValues(pref?.preferredCastes, self.caste);
  if (wanted.length === 0) return scoreComponent('community', 0, false);
  const values = [candidate.caste, candidate.community].filter(
    (v): v is string => typeof v === 'string' && v.trim().length > 0,
  );
  if (values.length === 0) return scoreComponent('community', 0, false);
  const hit = wanted.some((w) =>
    values.some((v) => v.trim().toLowerCase() === w.trim().toLowerCase()),
  );
  return scoreComponent('community', hit ? 1 : 0, true);
}

/**
 * The marital status a member stated they want, compared against the enum the
 * column actually holds.
 *
 * Both sides go through the filter's own [resolveMaritalStatuses], so the
 * picker's "Never Married" and the stored NEVER_MARRIED are the same value
 * here — they were not, and every candidate the filter accepted for marital
 * status then scored zero on it.
 */
function maritalStatusComponent(
  pref: PreferenceFilters | null,
  candidate: ScorableProfile,
): ScoreComponent {
  const wanted = resolveMaritalStatuses(pref?.maritalStatusPref);
  const have = resolveMaritalStatuses([candidate.maritalStatus ?? '']);
  if (wanted.length === 0 || have.length === 0) {
    return scoreComponent('maritalStatus', 0, false);
  }
  return scoreComponent(
    'maritalStatus',
    wanted.includes(have[0]) ? 1 : 0,
    true,
  );
}

/** City is a full match; same state is partial credit, not zero. */
function locationComponent(
  pref: PreferenceFilters | null,
  candidate: ScorableProfile,
  self: SelfAttributes,
): ScoreComponent {
  // The same split the filter applies: "Same State" names a state, not a city.
  const { cities, states } = resolveLocation(pref, self);
  if (cities.length === 0 && states.length === 0) {
    return scoreComponent('location', 0, false);
  }
  const eq = (a: string | null, b: string): boolean =>
    typeof a === 'string' && a.trim().toLowerCase() === b.trim().toLowerCase();

  if (cities.some((c) => eq(candidate.currentCity, c))) {
    return scoreComponent('location', 1, true);
  }
  if (states.some((s) => eq(candidate.currentState, s))) {
    return scoreComponent('location', 1, true);
  }
  // Right state, wrong city — meaningfully closer than a different state.
  if (
    cities.length > 0 &&
    eq(candidate.currentState ?? null, self.currentState ?? '')
  ) {
    return scoreComponent('location', 0.5, true);
  }
  return scoreComponent('location', 0, true);
}

/**
 * Diet, smoking and drinking, read from extendedPreferences — the JSON blob
 * the standalone Partner Preferences page writes. Only keys that resolve to
 * a literal value count, so a UI placeholder never becomes a requirement.
 */
function lifestyleComponent(
  pref: PreferenceFilters | null,
  candidate: ScorableProfile,
): ScoreComponent {
  const ext = asRecord(pref?.extendedPreferences);
  const pairs: Array<[unknown, string | null]> = [
    [ext.dietPref ?? ext.diet, candidate.dietaryHabits],
    [ext.smokingPref ?? ext.smoking, candidate.smokingHabits],
    [ext.drinkingPref ?? ext.drinking, candidate.drinkingHabits],
  ];

  let stated = 0;
  let matched = 0;
  for (const [want, have] of pairs) {
    if (typeof want !== 'string' || !isLiteral(want) || !have) continue;
    stated++;
    if (want.trim().toLowerCase() === have.trim().toLowerCase()) matched++;
  }
  if (stated === 0) return scoreComponent('lifestyle', 0, false);
  return scoreComponent('lifestyle', matched / stated, true);
}

function ageOf(dob: Date | null): number | null {
  if (!dob) return null;
  const ms = Date.now() - dob.getTime();
  if (ms <= 0) return null;
  return Math.floor(ms / (365.25 * MS_PER_DAY));
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}
