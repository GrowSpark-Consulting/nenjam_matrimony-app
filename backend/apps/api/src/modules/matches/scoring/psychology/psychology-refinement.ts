import { PSYCHOLOGY_REFINEMENT } from '../matching-weights.config';
import { calculatePsychologyCompatibility } from '../../../psychology/scoring/psychology-compatibility.calculator';
import type { ScoringQuestion } from '../../../psychology/scoring/psychology-compatibility.types';
import {
  errorMessage,
  warnThrottled,
} from '../../../psychology/scoring/psychology-log';
import { Logger } from '@nestjs/common';

const logger = new Logger('PsychologyRefinement');

/** A pair's marriage-compatibility result, reduced to what ranking uses. */
export interface PsychologyPairScore {
  /** 0-100, the approved matrix average with the hard-axis ceiling applied. */
  score: number;
  /** The pair gave the hard-axis question's dealbreaker combination. */
  hardAxisConflict: boolean;
}

/**
 * The pair's psychology result, or null when psychology does not apply to this
 * pair. Null is the ONLY outcome for every kind of absence or failure: a side
 * without answers, no questions supplied, answers that don't cover every
 * question, malformed data, or an unexpected exception. Callers treat null as
 * "no refinement" — the pair keeps its ordinary score, which is what a member
 * who did not take the quiz gets.
 *
 * Symmetric: the result is the same whichever member is the seeker.
 */
export function psychologyPairScore(
  seekerAnswers: Record<string, string> | null | undefined,
  candidateAnswers: Record<string, string> | null | undefined,
  questions: readonly ScoringQuestion[] | undefined,
): PsychologyPairScore | null {
  if (!seekerAnswers || !candidateAnswers || !questions?.length) return null;

  try {
    const result = calculatePsychologyCompatibility(
      questions,
      seekerAnswers,
      candidateAnswers,
      { includeFlags: false },
    );
    // A partial pair is not comparable with a full one (and could have skipped
    // the hard-axis question), so it does not count.
    if (!result.complete || result.overallScore === null) return null;
    return {
      score: result.overallScore,
      hardAxisConflict: result.hardAxisConflict,
    };
  } catch (error) {
    // Discover must never fail because of psychology: this one pair simply
    // gets no refinement.
    warnThrottled(
      logger,
      'pair-scoring-failed',
      `Psychology scoring threw for a candidate pair; that pair is ranked without psychology: ${errorMessage(error)}`,
    );
    return null;
  }
}

/**
 * The ranking-point refinement for a pair — see PSYCHOLOGY_REFINEMENT for the
 * rationale. Pure. Exactly 0 for null, and for every pair that is merely
 * average or below without a hard-axis conflict.
 */
export function psychologyRefinement(pair: PsychologyPairScore | null): number {
  if (!pair) return 0;
  const { neutralScore, maxBonus, hardAxisPenalty } = PSYCHOLOGY_REFINEMENT;

  if (pair.hardAxisConflict) return -hardAxisPenalty;

  const fraction = (pair.score - neutralScore) / (100 - neutralScore);
  const bonus = maxBonus * Math.min(1, Math.max(0, fraction));
  // Two decimals: enough to order pairs, and stable across a cursor round trip.
  return Math.round(bonus * 100) / 100;
}
