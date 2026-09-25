/**
 * Every number the compatibility engine uses, in one place.
 *
 * These will change once there is real engagement data to tune against, and a
 * weight buried inside a service is a weight nobody dares to touch. Keeping
 * them here means retuning is a one-file diff, and the unit tests assert the
 * set still sums to 100 so a future edit cannot silently skew the scale.
 */

/**
 * Which scoring formula produced a compatibility result.
 *
 * `v1-preference`: partner-preference fit in both directions, blended 60/40,
 * plus the three candidate-quality signals, under the weights below. Bump it
 * whenever a signal is added, a weight changes, or a fix changes what a
 * component returns, so a stored or logged score can always be traced to the
 * formula that made it.
 *
 * `v1.1-preference`: marital status and "Same State" read the preference the
 * way the filter does. Before, a "Never Married" preference never matched the
 * stored NEVER_MARRIED, and "Same State" was compared against the seeker's
 * city — so candidates the filter had accepted scored as mismatches.
 *
 * `v1.2-preference`: education and occupation preferences apply at all. Their
 * picker options are categories ("B.E / B.Tech+", "Software / IT") mapped to
 * the profile values they cover (filters/preference-categories.ts); before,
 * every one was dropped as a UI label and the preference never counted.
 *
 * `v1.3-psychology-refinement`: adds the marriage-compatibility quiz as a
 * bounded refinement of the RANKING key only (see PSYCHOLOGY_REFINEMENT below).
 * The weighted 100-point model, every member-visible score and the band are
 * untouched: a pair with no usable quiz data scores exactly as under
 * `v1.2-preference`, and a pair with it has the same visible score plus a
 * small ordering nudge. (An earlier build added psychology as a 15-weight
 * component, taking the total to 115; that model is gone.)
 */
export const MATCHING_ALGORITHM_VERSION = 'v1.3-psychology-refinement';

/** A single scored dimension. */
export type ScoreKey =
  | 'age'
  | 'location'
  | 'education'
  | 'profession'
  | 'religion'
  | 'community'
  | 'motherTongue'
  | 'height'
  | 'maritalStatus'
  | 'lifestyle'
  | 'profileCompleteness'
  | 'verification'
  | 'activity';

/**
 * Weights for the one-directional score (how well a candidate fits the
 * seeker's stated preferences) plus the three candidate-quality signals that
 * are not preference-based at all.
 *
 * Rationale, dimension by dimension:
 *
 *  age 14            The most consistently stated and most consistently
 *                    enforced preference in Indian matrimony. Highest single
 *                    preference weight.
 *  religion 12       Effectively a hard requirement for most families. It is
 *                    scored rather than filtered so that a member who left it
 *                    blank is not silently excluded from everyone's results.
 *  community 11      Caste/community. Nearly as decisive as religion in this
 *                    market, but more often left as "Any Caste", so slightly
 *                    lower.
 *  motherTongue 9    Strong signal in a Tamil-first product, where language
 *                    frequently stands in for regional and cultural fit.
 *  location 9        Where the candidate lives. Deliberately below language:
 *                    families relocate for marriage, so distance informs
 *                    rather than decides.
 *  education 8       Commonly stated, but the stored values are noisy — the
 *                    UI writes grouped labels like "B.E / B.Tech+" which are
 *                    not literal profile values. Weighted for what it can
 *                    actually resolve.
 *  profession 7      Same noise problem as education, and more tolerated in
 *                    practice once other signals align.
 *  maritalStatus 6   Matters enormously to the minority it applies to and not
 *                    at all to everyone else. A low flat weight is the honest
 *                    treatment; a high one would distort the common case.
 *  height 5          Frequently stated, rarely decisive.
 *  lifestyle 4       Diet, smoking, drinking. Real signal, weakly stated —
 *                    most members never set a preference for it.
 *
 *                    ── the following are candidate quality, not preference ──
 *
 *  profileCompleteness 6   Complete profiles convert better and this rewards
 *                          finishing the wizard. Uses the already-computed
 *                          profileCompletePct, so it costs nothing to read.
 *  verification 6          Trust signal from User.trustScore. Meaningful but
 *                          capped, so an unverified member is never buried.
 *  activity 3              Weakest weight because the underlying data is a
 *                          proxy — see ACTIVITY_NOTE below. Raise it once a
 *                          real lastActiveAt exists.
 */
export const MATCHING_WEIGHTS: Readonly<Record<ScoreKey, number>> =
  Object.freeze({
    age: 14,
    religion: 12,
    community: 11,
    motherTongue: 9,
    location: 9,
    education: 8,
    profession: 7,
    maritalStatus: 6,
    height: 5,
    lifestyle: 4,
    profileCompleteness: 6,
    verification: 6,
    activity: 3,
  });

/**
 * There is no `lastActiveAt` column on User or UserProfile. `updatedAt` is
 * used instead and is an honest proxy at best: it moves when a profile is
 * edited, not when someone opens the app. Its weight is deliberately the
 * lowest in the set for that reason, and it should be raised — not the formula
 * changed — once a real activity timestamp is recorded.
 */
export const ACTIVITY_NOTE =
  'activity is derived from UserProfile.updatedAt; no lastActiveAt column exists yet';

/** Days after which the activity signal has fully decayed to zero. */
export const ACTIVITY_DECAY_DAYS = 45;

/**
 * How the two directions combine for the mutual score.
 *
 * Not 50/50. The seeker's own preferences should still dominate what they are
 * shown — a feed that over-weights the other side starts recommending people
 * the member did not ask for, however likely they are to reply. 60/40 keeps
 * the member's intent in charge while making "will they reply" a real factor.
 */
export const MUTUAL_BLEND = Object.freeze({
  seekerToCandidate: 0.6,
  candidateToSeeker: 0.4,
});

/**
 * Bands for display. The API returns the raw 0-100 integer, but the UI should
 * show a band: a member who sees 87 will ask why it is not 90, and there is no
 * defensible answer. 87 and 86 mean the same thing.
 */
export const SCORE_BANDS: ReadonlyArray<{ min: number; label: string }> =
  Object.freeze([
    { min: 80, label: 'Excellent' },
    { min: 60, label: 'Very good' },
    { min: 40, label: 'Good' },
    { min: 0, label: 'Fair' },
  ]);

export function scoreBand(score: number): string {
  return SCORE_BANDS.find((b) => score >= b.min)?.label ?? 'Fair';
}

/**
 * How the marriage-compatibility quiz nudges ORDER. It is deliberately not a
 * weight in the model above.
 *
 * Why not a weight. Any weight enters the weighted mean's numerator AND
 * denominator, and only for pairs where both members took the quiz. That makes
 * two populations incomparable in one ranked list: a quiz score below a
 * member's preference fit (typical, since preference fit inside a filtered
 * feed is high) pulls that member's mean DOWN, so completing the quiz cost
 * rank. And when a seeker has stated few preferences, the same weight became
 * half the whole score. A refinement added to the finished score has neither
 * problem: it never touches the denominator, and no quiz data means +0.
 *
 * The rule, in ranking points on the same 0-100 scale as the score:
 *
 *   - Never negative for merely being an average or unremarkable pair. Below
 *     `neutralScore` the refinement is 0, exactly what a member who did not
 *     take the quiz gets. (`neutralScore` sits below the ~66 mean of a random
 *     pair on purpose, so a typical pair is never penalised.)
 *   - Above it, a bonus rising linearly to `maxBonus` at a perfect 100.
 *   - The one negative case is a hard-axis conflict (the children question's
 *     dealbreaker pair): `hardAxisPenalty`. That is a declared, specific
 *     incompatibility between two members who BOTH answered — not a penalty for
 *     taking the quiz, and never applied to anyone who did not.
 *
 * Bounds, so it can refine but never dominate: the bonus is at most
 * `maxBonus` (6) and the penalty at most `hardAxisPenalty` (10), on a base that
 * keeps its full 0-100 range. A candidate more than 16 base points ahead can
 * never be overtaken by psychology alone (asserted in the tests).
 *
 * Retuning: change these numbers and bump MATCHING_ALGORITHM_VERSION.
 */
export const PSYCHOLOGY_REFINEMENT = Object.freeze({
  neutralScore: 60,
  maxBonus: 6,
  hardAxisPenalty: 10,
});

/** Sum of all weights. Asserted by the unit tests to be exactly 100. */
export function totalWeight(): number {
  return Object.values(MATCHING_WEIGHTS).reduce((a, b) => a + b, 0);
}
