import type { PreferenceFilters } from '../filters/partner-preference-where.builder';

export interface FallbackConfig {
  enabled: boolean;
  ageRelaxStep1: number;
  ageRelaxStep2: number;
  maxTier: number;
}

export interface TierDefinition {
  tier: number;
  /** The `PreferenceFilters` to run through [buildFeedWhere] for this tier.
   *  `null` (Tier 10 only) means gender-only — no preference filtering at all. */
  pref: PreferenceFilters | null;
  /** Preference categories relaxed so far, cumulative, for the API response's
   *  `relaxedFilters` and the UI banner. Empty at Tier 1. */
  relaxedFilters: string[];
  /** Human-readable reason surfaced in the API response / UI banner. */
  reason: string;
}

const PLATFORM_MIN_AGE = 18;

/**
 * Builds the ordered list of tiers ProgressiveFallbackStrategy tries in turn,
 * stopping at the first with candidates > 0. Pure and deterministic: same
 * inputs always produce the same plan, independent of the database.
 *
 * Tier 1 is always the caller's exact saved preference, untouched — mirrors
 * the existing recommendation engine exactly. Tiers 2-9 progressively relax
 * one signal at a time (see each tier's `mutate`); Tier 10 drops every
 * preference and matches on gender alone.
 *
 * If the caller has no saved preference at all, Tier 1 (gender-only, since
 * `buildFeedWhere` treats `pref: null` as "no preference filtering") is
 * already the loosest possible state — there is nothing left to relax, so
 * the plan is just that one tier.
 */
export function buildTierPlan(
  originalPref: PreferenceFilters | null,
  config: FallbackConfig,
): TierDefinition[] {
  const tier1: TierDefinition = {
    tier: 1,
    pref: originalPref,
    relaxedFilters: [],
    reason: 'Exact match on your saved preferences.',
  };

  if (!originalPref) {
    return [tier1];
  }

  const tiers: TierDefinition[] = [tier1];
  const relaxed: string[] = [];
  let current: PreferenceFilters = { ...originalPref };

  const addTier = (
    tier: number,
    label: string,
    reason: string,
    mutate: (pref: PreferenceFilters) => PreferenceFilters,
  ): void => {
    current = mutate(current);
    if (!relaxed.includes(label)) relaxed.push(label);
    tiers.push({ tier, pref: { ...current }, relaxedFilters: [...relaxed], reason });
  };

  addTier(
    2,
    'Age',
    `No exact matches found. Age range widened by ${config.ageRelaxStep1} years.`,
    (pref) => ({
      ...pref,
      minAge: relaxAge(originalPref.minAge, -config.ageRelaxStep1),
      maxAge: relaxAge(originalPref.maxAge, config.ageRelaxStep1),
    }),
  );

  addTier(
    3,
    'City',
    'No exact matches found. City filter relaxed — still matching within your state.',
    (pref) => ({ ...pref, preferredCities: keepOnlySameState(pref.preferredCities) }),
  );

  addTier(
    4,
    'Caste',
    'No exact matches found. Caste filter relaxed — still matching your religion.',
    (pref) => ({ ...pref, preferredCastes: [] }),
  );

  addTier(
    5,
    'Mother Tongue',
    'No exact matches found. Mother tongue filter relaxed.',
    (pref) => ({ ...pref, preferredMotherTongues: [] }),
  );

  addTier(
    6,
    'Education',
    'No exact matches found. Education filter relaxed.',
    (pref) => ({ ...pref, preferredEducation: [] }),
  );

  addTier(
    7,
    'Profession',
    'No exact matches found. Profession filter relaxed.',
    (pref) => ({ ...pref, preferredOccupations: [] }),
  );

  addTier(
    8,
    'Income',
    'No exact matches found. Income filter relaxed.',
    (pref) => ({ ...pref, minIncomeLakhs: null }),
  );

  addTier(
    9,
    'Age',
    `No exact matches found. Age range widened further (up to ${config.ageRelaxStep2} years).`,
    (pref) => ({
      ...pref,
      minAge: relaxAge(originalPref.minAge, -config.ageRelaxStep2),
      maxAge: relaxAge(originalPref.maxAge, config.ageRelaxStep2),
    }),
  );

  tiers.push({
    tier: 10,
    pref: null,
    relaxedFilters: [
      ...relaxed,
      'Height',
      'Religion',
      'State',
      'Marital Status',
      'Lifestyle',
    ],
    reason: 'No matches found even with relaxed preferences. Showing compatible profiles by gender only.',
  });

  return tiers.filter((t) => t.tier <= config.maxTier);
}

function relaxAge(
  value: number | null | undefined,
  delta: number,
): number | null | undefined {
  if (typeof value !== 'number' || !Number.isFinite(value)) return value;
  return Math.max(PLATFORM_MIN_AGE, value + delta);
}

/** Tier 3 ("ignore City, keep State"): `preferredCities` carries both
 *  city-level tokens ("Same City", literal cities) and the "Same State"
 *  meta-token (buildFeedWhere routes it to the state column) — so relaxing
 *  city means keeping only "Same State" and dropping everything else from
 *  this array. `preferredStates` is untouched, independently. */
function keepOnlySameState(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (v) => typeof v === 'string' && v.trim().toLowerCase() === 'same state',
  );
}
