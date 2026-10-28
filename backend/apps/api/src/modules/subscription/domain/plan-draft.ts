import {
  FEATURE_KEYS,
  parseEntitlements,
  reductionsBetween,
  validateEntitlementsForPublish,
  type EntitlementMap,
  type FeatureKey,
} from '../../entitlements/catalog/feature-catalog';
import type {
  CatalogDuration,
  CatalogPlan,
  CatalogVersion,
} from '../../entitlements/domain/membership.types';

/** One proposed duration (a purchasable plan length and its price). */
export interface DraftDuration {
  months: number;
  durationDays: number;
  bonusDays: number;
  /** Integer paise; null = not priced (never purchasable). */
  priceInPaise: number | null;
  isActive: boolean;
}

export interface DurationChange {
  months: number;
  before: DraftDuration | null;
  after: DraftDuration;
}

/** What publishing a draft would do, and whether it may. */
export interface DraftReview {
  entitlementProblems: string[];
  durationProblems: string[];
  /** Features whose value differs from the plan's current version. */
  changedFeatures: FeatureKey[];
  /** Of those, the ones that give members less — new purchases only;
   *  existing subscribers keep the version they bought. */
  reductionsVsCurrent: FeatureKey[];
  durationChanges: DurationChange[];
  hasChanges: boolean;
  publishable: boolean;
}

/** Postgres INTEGER — the column type of every paise amount. */
const MAX_PAISE = 2_147_483_647;

export function toDraftDuration(duration: CatalogDuration): DraftDuration {
  return {
    months: duration.months,
    durationDays: duration.durationDays,
    bonusDays: duration.bonusDays,
    priceInPaise: duration.priceInPaise,
    isActive: duration.isActive,
  };
}

/**
 * Reads a stored or submitted duration list. Returns the durations it could
 * read and every problem; never throws (a draft may be saved half-finished,
 * and is only refused at submit/publish).
 */
export function parseDraftDurations(
  planCode: string,
  raw: unknown,
  current: readonly CatalogDuration[],
): { durations: DraftDuration[]; problems: string[] } {
  const problems: string[] = [];
  if (!Array.isArray(raw)) {
    return { durations: [], problems: ['durations must be a list.'] };
  }
  if (planCode === 'FREE' && raw.length > 0) {
    problems.push('The Free plan has no price or durations.');
  }
  const durations: DraftDuration[] = [];
  const seen = new Set<number>();
  raw.forEach((item: unknown, index) => {
    const where = `durations[${index}]`;
    if (typeof item !== 'object' || item === null) {
      problems.push(`${where} must be an object.`);
      return;
    }
    const d = item as Record<string, unknown>;
    const months = d.months;
    if (!isInt(months, 1, 36)) {
      problems.push(`${where}.months must be a whole number from 1 to 36.`);
      return;
    }
    if (seen.has(months)) {
      problems.push(`${months} months is listed twice.`);
      return;
    }
    seen.add(months);
    const label = `${months} months`;
    if (!isInt(d.durationDays, 1, 3660)) {
      problems.push(
        `${label}: durationDays must be a whole number from 1 to 3660.`,
      );
    }
    if (!isInt(d.bonusDays, 0, 366)) {
      problems.push(
        `${label}: bonusDays must be a whole number from 0 to 366.`,
      );
    }
    if (d.priceInPaise !== null && !isInt(d.priceInPaise, 1, MAX_PAISE)) {
      problems.push(
        `${label}: priceInPaise must be a whole number of paise above 0, or null for "not priced".`,
      );
    }
    if (typeof d.isActive !== 'boolean') {
      problems.push(`${label}: isActive must be true or false.`);
    } else if (d.isActive && d.priceInPaise === null) {
      problems.push(`${label}: must be priced before it can be on sale.`);
    }
    durations.push({
      months,
      durationDays: d.durationDays as number,
      bonusDays: d.bonusDays as number,
      priceInPaise: d.priceInPaise as number | null,
      isActive: d.isActive as boolean,
    });
  });
  for (const existing of current) {
    if (!seen.has(existing.months)) {
      problems.push(
        `${existing.months} months can't be removed — keep it and set it off sale (isActive: false).`,
      );
    }
  }
  durations.sort((a, b) => a.months - b.months);
  return { durations, problems };
}

/**
 * Compares a draft with the plan as it is now. Publishable means: valid
 * entitlements (every feature, nothing unknown, safety features on), valid
 * durations, and at least one change.
 */
export function reviewDraft(
  plan: CatalogPlan,
  current: CatalogVersion | null,
  draft: { entitlements: unknown; durations: unknown },
): DraftReview & { entitlements: EntitlementMap; durations: DraftDuration[] } {
  const entitlementProblems = validateEntitlementsForPublish(
    draft.entitlements,
  );
  const entitlements = parseEntitlements(draft.entitlements).map;
  const { durations, problems: durationProblems } = parseDraftDurations(
    plan.code,
    draft.durations,
    plan.durations,
  );

  const changedFeatures = current
    ? FEATURE_KEYS.filter(
        (key) =>
          canonical(current.entitlements[key]) !== canonical(entitlements[key]),
      )
    : [...FEATURE_KEYS];
  const reductionsVsCurrent = current
    ? reductionsBetween(current.entitlements, entitlements)
    : [];

  const durationChanges: DurationChange[] = [];
  for (const after of durations) {
    const existing = plan.durations.find((d) => d.months === after.months);
    const before = existing ? toDraftDuration(existing) : null;
    if (!before || canonical(before) !== canonical(after)) {
      durationChanges.push({ months: after.months, before, after });
    }
  }

  const hasChanges = changedFeatures.length > 0 || durationChanges.length > 0;
  return {
    entitlements,
    durations,
    entitlementProblems,
    durationProblems,
    changedFeatures,
    reductionsVsCurrent,
    durationChanges,
    hasChanges,
    publishable:
      entitlementProblems.length === 0 &&
      durationProblems.length === 0 &&
      hasChanges,
  };
}

/** JSON with object keys sorted, so key order never reads as a change. */
export function canonical(value: unknown): string {
  return JSON.stringify(value, (_key, v: unknown) =>
    v && typeof v === 'object' && !Array.isArray(v)
      ? Object.fromEntries(
          Object.entries(v as Record<string, unknown>).sort(([a], [b]) =>
            a.localeCompare(b),
          ),
        )
      : v,
  );
}

function isInt(value: unknown, min: number, max: number): value is number {
  return (
    typeof value === 'number' &&
    Number.isInteger(value) &&
    value >= min &&
    value <= max
  );
}
