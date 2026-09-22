/**
 * What the Partner Preferences picker's education and occupation options MEAN,
 * in terms of the values members actually store on their profile.
 *
 * The two vocabularies were never connected. The preference picker offers
 * categories ("B.E / B.Tech+", "Software / IT"); the profile picker stores
 * specific values ("B.E / B.Tech", "Software Engineer"). And because both sets
 * contain "/", the generic rule that treats a "/" value as a UI group label
 * dropped every one of them — so an education preference was never applied,
 * not even one that exactly equalled a member's own education.
 *
 * Mapping, as agreed for the product:
 *  - A "+" option means that level or higher.
 *  - A category covers the specific profile values listed against it.
 *
 * Both sides are copied from the Flutter app. They are pinned by
 * preference-categories.spec.ts, which reads the Dart source and fails if a
 * value here stops matching an option a member can actually pick — the same
 * drift guard the app uses for the draft DTOs.
 *   Profile values:    Frontend/lib/core/constants/profile_options.dart
 *                      (ProfileOptions.qualifications / .occupations)
 *   Preference labels: Frontend/lib/features/registration/presentation/utils/
 *                      partner_preference_labels.dart
 */

/** Preference label → the profile `highestEducation` values it covers. */
export const EDUCATION_CATEGORIES: Readonly<Record<string, readonly string[]>> =
  Object.freeze({
    'B.E / B.Tech+': ['B.E / B.Tech', 'M.Tech / M.E', 'Ph.D'],
    'MBBS / MD+': ['MBBS / MD'],
    'MBA+': ['MBA / PGDM', 'Ph.D'],
  });

/** Preference label → the profile `profession` values it covers. */
export const OCCUPATION_CATEGORIES: Readonly<
  Record<string, readonly string[]>
> = Object.freeze({
  'Software / IT': ['Software Engineer'],
  Doctor: ['Doctor'],
  Government: ['IAS / IPS / Govt'],
  Business: ['Business Owner'],
});

/** Every value a member can pick for their own education. */
export const PROFILE_QUALIFICATIONS: readonly string[] = [
  'B.E / B.Tech',
  'M.Tech / M.E',
  'MBBS / MD',
  'MBA / PGDM',
  'B.Sc / M.Sc',
  'CA / CFA',
  'B.Com / M.Com',
  'Ph.D',
  'Diploma',
];

/** Every value a member can pick for their own occupation. */
export const PROFILE_OCCUPATIONS: readonly string[] = [
  'Software Engineer',
  'Doctor',
  'IAS / IPS / Govt',
  'Business Owner',
  'Finance / Banking',
  'Civil / Mechanical Engg',
  'Teacher / Professor',
  'Lawyer',
  'Architect',
];

/**
 * Resolves raw preference tokens to the concrete profile values they match.
 *
 *  - a known category → every profile value it covers;
 *  - an exact profile value (even one containing "/") → itself;
 *  - anything else → [fallback], the generic resolver, so free-text or legacy
 *    values keep working exactly as before and "Any" stays "no preference".
 *
 * Matching is case-insensitive on the way in; values come back in their
 * canonical spelling, de-duplicated, in first-seen order.
 */
function resolveAgainst(
  raw: unknown,
  categories: Readonly<Record<string, readonly string[]>>,
  profileValues: readonly string[],
  fallback: (token: string) => string[],
): string[] {
  const byCategory = new Map(
    Object.entries(categories).map(([label, values]) => [
      label.trim().toLowerCase(),
      values,
    ]),
  );
  const byValue = new Map(
    profileValues.map((v) => [v.trim().toLowerCase(), v]),
  );

  const out: string[] = [];
  const seen = new Set<string>();
  const push = (value: string): void => {
    const key = value.toLowerCase();
    if (!seen.has(key)) {
      seen.add(key);
      out.push(value);
    }
  };

  if (!Array.isArray(raw)) return out;
  for (const item of raw) {
    if (typeof item !== 'string') continue;
    const token = item.trim();
    if (!token) continue;
    const key = token.toLowerCase();
    const category = byCategory.get(key);
    if (category) category.forEach(push);
    else if (byValue.has(key)) push(byValue.get(key)!);
    else fallback(token).forEach(push);
  }
  return out;
}

/** The profile education values a stored education preference matches. */
export function resolveEducationPreference(
  raw: unknown,
  fallback: (token: string) => string[],
): string[] {
  return resolveAgainst(
    raw,
    EDUCATION_CATEGORIES,
    PROFILE_QUALIFICATIONS,
    fallback,
  );
}

/** The profile occupation values a stored occupation preference matches. */
export function resolveOccupationPreference(
  raw: unknown,
  fallback: (token: string) => string[],
): string[] {
  return resolveAgainst(
    raw,
    OCCUPATION_CATEGORIES,
    PROFILE_OCCUPATIONS,
    fallback,
  );
}
