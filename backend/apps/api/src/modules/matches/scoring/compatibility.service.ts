import { Injectable } from '@nestjs/common';
import type { PreferenceFilters } from '../filters/partner-preference-where.builder';
import type { ScoringQuestion } from '../../psychology/scoring/psychology-compatibility.types';
import {
  MATCHING_ALGORITHM_VERSION,
  MUTUAL_BLEND,
  scoreBand,
  type ScoreKey,
} from './matching-weights.config';
import type {
  CompatibilityInput,
  CompatibilitySignal,
  ScorableProfile,
  ScoreComponent,
} from './compatibility-signal';
import { PREFERENCE_COMPATIBILITY_SIGNAL } from './preference/preference-compatibility.signal';
import { CANDIDATE_QUALITY_SIGNAL } from './quality/candidate-quality.signal';
import {
  psychologyPairScore,
  psychologyRefinement,
} from './psychology/psychology-refinement';

// Re-exported so existing importers keep one place to take scoring types from.
export type { ScorableProfile, ScoreComponent } from './compatibility-signal';

export interface CompatibilityBreakdown {
  /** 0-100, seeker's preferences against the candidate. */
  seekerFit: number;
  /** 0-100, candidate's preferences against the seeker. Null when the
   *  candidate has saved no preference at all. */
  mutualFit: number | null;
  /** 0-100 blended headline number. */
  overall: number;
  band: string;
  components: ScoreComponent[];
  /**
   * The seeker's stated preferences this candidate fully meets, in component
   * order — `compatibility` signals only, never quality. For debugging and
   * future explanation UI; not part of the API response.
   */
  matchedPreferences: ScoreKey[];
  /** Stated preferences met partly or not at all (ratio below 1). Unstated
   *  preferences appear in neither list. */
  unmatchedPreferences: ScoreKey[];
  /** The formula that produced this result — see MATCHING_ALGORITHM_VERSION. */
  algorithmVersion: string;
  /**
   * The score RankingService orders by: the member-visible score above plus the
   * marriage-compatibility refinement (see PSYCHOLOGY_REFINEMENT).
   *
   * Every field above is exactly what it was before psychology existed, for
   * every pair — including pairs where both members took the quiz. Only this
   * one moves, and it is never sent to a client: exposing it would let a member
   * read another's quiz answers back out of a score, one retake at a time.
   * `psychologyRefinement` is 0 whenever psychology does not apply, which makes
   * `ranking` equal the visible score. Always set by CompatibilityService;
   * optional only so a hand-built breakdown (tests) stays valid, in which case
   * RankingService orders by the visible score.
   */
  ranking?: {
    overall: number;
    mutualFit: number | null;
    psychologyRefinement: number;
  };
}

/** What CompatibilityService returns: a breakdown whose ranking key is set. */
export type ScoredBreakdown = CompatibilityBreakdown &
  Required<Pick<CompatibilityBreakdown, 'ranking'>>;

/**
 * Every signal the score is built from, in the order their components appear.
 *
 * A new signal is added here and nowhere else — FeedService, RankingService,
 * the candidate query and the API response do not change. Its ScoreKeys and
 * weights go in matching-weights.config.ts (which keeps the total at 100), and
 * MATCHING_ALGORITHM_VERSION is bumped.
 */
const SIGNALS: readonly CompatibilitySignal[] = [
  PREFERENCE_COMPATIBILITY_SIGNAL,
  CANDIDATE_QUALITY_SIGNAL,
];

/** Keys whose outcome is explained as matched / unmatched preferences. */
const EXPLAINED_KEYS: ReadonlySet<ScoreKey> = new Set(
  SIGNALS.filter((s) => s.kind === 'compatibility').flatMap((s) => s.keys),
);

/**
 * Turns two profiles into a 0-100 compatibility score by aggregating signals.
 *
 * Three rules shape the whole design:
 *
 *  1. Nothing here filters. Hard eligibility — blocks, bans, deletions,
 *     gender, incomplete profiles, declined interests — stays in
 *     eligibility.builder. A candidate that reaches this service has
 *     already been proven eligible; scoring only decides ORDER. Moving a
 *     safety rule in here would make it silently bypassable by a weight change.
 *
 *  2. An unstated preference is not a failure. A signal marks it inapplicable
 *     and its weight is removed from the denominator rather than scored as
 *     zero. Otherwise every member who skipped half the preference form would
 *     score ~40% against everyone, and the ranking would measure form-filling
 *     rather than fit.
 *
 *  3. Both directions run the same signals. "Does she meet my preferences" and
 *     "do I meet hers" are one CompatibilityInput with the roles swapped, so
 *     they can never drift apart.
 *
 *  4. Psychology is a refinement of ORDER, not a component of the score. The
 *     marriage-compatibility quiz is not in SIGNALS, has no weight, and enters
 *     no numerator or denominator, so the 100-point model and every
 *     member-visible number are exactly what they are without it. A pair with
 *     no usable quiz data — either member hasn't taken it, data is stale or
 *     malformed, scoring fails — gets no refinement, never a penalty. See
 *     PSYCHOLOGY_REFINEMENT for the numbers and why.
 */
@Injectable()
export class CompatibilityService {
  /**
   * Full breakdown for one pair. Pure — no I/O, safe to call in a loop.
   *
   * `psychologyQuestions` (with `psychologyAnswers` on both profiles) enables
   * the psychology refinement of the ranking key; omit it and the result is
   * exactly the pre-psychology one.
   */
  score(
    seeker: ScorableProfile,
    seekerPreference: PreferenceFilters | null,
    candidate: ScorableProfile,
    psychologyQuestions?: readonly ScoringQuestion[],
  ): ScoredBreakdown {
    const components = this.components({
      chooser: seeker,
      preference: seekerPreference,
      candidate,
    });
    const seekerFit = this.total(components);

    const mutualFit = candidate.preference
      ? this.total(
          this.components({
            chooser: candidate,
            preference: candidate.preference,
            candidate: seeker,
          }),
        )
      : null;

    const overall =
      mutualFit === null
        ? seekerFit
        : Math.round(
            seekerFit * MUTUAL_BLEND.seekerToCandidate +
              mutualFit * MUTUAL_BLEND.candidateToSeeker,
          );

    // Psychology is symmetric — the pair scores the same whichever member is
    // the seeker — so it is computed once and added to the ordering key only.
    // It is not a component, so it is in no numerator or denominator above.
    const refinement = psychologyRefinement(
      psychologyPairScore(
        seeker.psychologyAnswers,
        candidate.psychologyAnswers,
        psychologyQuestions,
      ),
    );

    const explained = components.filter(
      (c) => c.applicable && EXPLAINED_KEYS.has(c.key),
    );

    return {
      seekerFit,
      mutualFit,
      overall,
      band: scoreBand(overall),
      components,
      matchedPreferences: explained
        .filter((c) => c.ratio === 1)
        .map((c) => c.key),
      unmatchedPreferences: explained
        .filter((c) => c.ratio < 1)
        .map((c) => c.key),
      algorithmVersion: MATCHING_ALGORITHM_VERSION,
      ranking: {
        overall: rankingScore(overall, refinement),
        mutualFit:
          mutualFit === null ? null : rankingScore(mutualFit, refinement),
        psychologyRefinement: refinement,
      },
    };
  }

  /** Scores a page of candidates against one seeker. */
  scoreMany(
    seeker: ScorableProfile,
    seekerPreference: PreferenceFilters | null,
    candidates: ScorableProfile[],
    psychologyQuestions?: readonly ScoringQuestion[],
  ): Map<string, ScoredBreakdown> {
    const out = new Map<string, ScoredBreakdown>();
    for (const c of candidates) {
      out.set(
        c.userId,
        this.score(seeker, seekerPreference, c, psychologyQuestions),
      );
    }
    return out;
  }

  // ── internals ──────────────────────────────────────────────────────────

  private components(input: CompatibilityInput): ScoreComponent[] {
    return SIGNALS.flatMap((signal) => signal.components(input));
  }

  /**
   * Weighted mean over applicable components only. Dividing by the applicable
   * weight rather than by 100 is what implements rule 2 above: a seeker who
   * stated three preferences is scored out of those three.
   */
  private total(components: ScoreComponent[]): number {
    let earned = 0;
    let possible = 0;
    for (const c of components) {
      if (!c.applicable) continue;
      earned += c.points;
      possible += c.weight;
    }
    if (possible === 0) return 0;
    return Math.round((earned / possible) * 100);
  }
}

/**
 * A visible score plus its refinement, as the ordering key. Floored at 0 and
 * deliberately NOT capped at 100: a perfect-fit pair with excellent psychology
 * should still sort ahead of a perfect-fit pair without it, which a cap would
 * flatten. The key is internal, so it may exceed the 0-100 display range.
 */
function rankingScore(visible: number, refinement: number): number {
  return Math.max(0, Math.round((visible + refinement) * 100) / 100);
}
