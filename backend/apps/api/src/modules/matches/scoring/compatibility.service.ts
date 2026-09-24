import { Injectable } from '@nestjs/common';
import type { PreferenceFilters } from '../filters/partner-preference-where.builder';
import type { QuizQuestion } from '../../../../../../libs/database/generated/client';
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
import { PSYCHOLOGY_COMPATIBILITY_SIGNAL } from './psychology/psychology-compatibility.signal';

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
}

/**
 * Every signal the score is built from, in the order their components appear.
 *
 * A new signal is added here and nowhere else — FeedService, RankingService,
 * the candidate query and the API response do not change. Its ScoreKeys and
 * weights go in matching-weights.config.ts, and MATCHING_ALGORITHM_VERSION is
 * bumped.
 *
 * PSYCHOLOGY_COMPATIBILITY_SIGNAL is the one exception to "nothing else
 * changes": it needs data no other signal does (each side's quiz answers,
 * plus the quiz's questions as shared context), so `score()`/`scoreMany()`
 * below take an optional extra argument for it. Every existing caller omits
 * it, which is exactly what keeps this addition a no-op today.
 */
const SIGNALS: readonly CompatibilitySignal[] = [
  PREFERENCE_COMPATIBILITY_SIGNAL,
  PSYCHOLOGY_COMPATIBILITY_SIGNAL,
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
 */
@Injectable()
export class CompatibilityService {
  /**
   * Full breakdown for one pair. Pure — no I/O, safe to call in a loop.
   *
   * `psychologyQuestions` is optional and unused by any caller today — see
   * PSYCHOLOGY_COMPATIBILITY_SIGNAL's doc comment. Passing it (plus setting
   * `psychologyAnswers` on both ScorableProfiles) is what a future, separate
   * step would do to make that signal actually applicable for a real pair.
   */
  score(
    seeker: ScorableProfile,
    seekerPreference: PreferenceFilters | null,
    candidate: ScorableProfile,
    psychologyQuestions?: readonly QuizQuestion[],
  ): CompatibilityBreakdown {
    const components = this.components({
      chooser: seeker,
      preference: seekerPreference,
      candidate,
      psychologyQuestions,
    });
    const seekerFit = this.total(components);

    const mutualFit = candidate.preference
      ? this.total(
          this.components({
            chooser: candidate,
            preference: candidate.preference,
            candidate: seeker,
            psychologyQuestions,
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
    };
  }

  /** Scores a page of candidates against one seeker. */
  scoreMany(
    seeker: ScorableProfile,
    seekerPreference: PreferenceFilters | null,
    candidates: ScorableProfile[],
    psychologyQuestions?: readonly QuizQuestion[],
  ): Map<string, CompatibilityBreakdown> {
    const out = new Map<string, CompatibilityBreakdown>();
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
