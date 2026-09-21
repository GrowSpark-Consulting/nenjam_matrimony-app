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
 * whenever a signal is added or a weight changes, so a stored or logged score
 * can always be traced to the formula that made it.
 */
export const MATCHING_ALGORITHM_VERSION = 'v1-preference';

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
export const MATCHING_WEIGHTS: Readonly<Record<ScoreKey, number>> = Object.freeze({
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
export const SCORE_BANDS: ReadonlyArray<{ min: number; label: string }> = Object.freeze([
  { min: 80, label: 'Excellent' },
  { min: 60, label: 'Very good' },
  { min: 40, label: 'Good' },
  { min: 0, label: 'Fair' },
]);

export function scoreBand(score: number): string {
  return SCORE_BANDS.find((b) => score >= b.min)?.label ?? 'Fair';
}

/** Sum of all weights. Asserted by the unit tests to be exactly 100. */
export function totalWeight(): number {
  return Object.values(MATCHING_WEIGHTS).reduce((a, b) => a + b, 0);
}
