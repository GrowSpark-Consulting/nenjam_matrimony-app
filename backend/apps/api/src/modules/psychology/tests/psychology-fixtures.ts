import {
  QUESTIONS,
  QUIZ_ID,
} from '../../../../../../libs/database/src/seeders/quiz.seeder';
import type { ScoringQuestion } from '../scoring/psychology-compatibility.types';

/**
 * The REAL seeded quiz, as scoring sees it. Specs that need a realistic quiz
 * use this rather than hand-built questions so they exercise the same ids,
 * dimensions and scoring types production does.
 */
export { QUIZ_ID };

export const SEEDED_QUESTIONS = QUESTIONS;

export const SCORING_QUESTIONS: ScoringQuestion[] = QUESTIONS.map((q) => ({
  id: q.id,
  order: q.order,
  dimension: q.dimension,
  scoringType: q.scoringType,
}));

export const QUESTION_IDS = QUESTIONS.map((q) => q.id);

/** Every question answered with `key`. */
export function allAnswered(key: string): Record<string, string> {
  return Object.fromEntries(QUESTION_IDS.map((id) => [id, key]));
}

/** `base` with some answers overridden by question number (1-based). */
export function withAnswers(
  base: Record<string, string>,
  overrides: Record<number, string>,
): Record<string, string> {
  const out = { ...base };
  for (const [n, key] of Object.entries(overrides)) {
    out[QUESTION_IDS[Number(n) - 1]] = key;
  }
  return out;
}
