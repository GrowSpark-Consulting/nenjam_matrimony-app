import type { QuizQuestion } from '../../../../../../libs/database/generated/client';
import {
  PSYCHOLOGY_COMPATIBILITY_MATRIX,
  pairLookupKey,
} from './compatibility-matrix.data';
import {
  PsychologyCompatibilityFlag,
  QuestionCompatibilityBreakdown,
} from './psychology-compatibility.types';

// Q9's dimension — identifies the HARD_AXIS question generically (there is
// exactly one today) for the overall-score ceiling rule.
const HARD_AXIS_CEILING_DIMENSION = 'children';
const HARD_AXIS_CEILING = 40;

// Q10's dimension — the question whose (B,D)/(C,D) flag escalates when Q9
// shows a meaningful conflict.
const ESCALATION_TARGET_DIMENSION = 'life_stage_timeline';

// Q8's dimension — the question whose "D" (involve families) option gets an
// informational, score-neutral cross-check note against Q3.
const FAMILY_INVOLVEMENT_DECISION_DIMENSION = 'decision_making';
const FAMILY_INVOLVEMENT_DECISION_KEY = 'D';
const FAMILY_BOUNDARIES_DIMENSION = 'family_boundaries';

interface RawPairRule {
  pair: [string, string];
  type: 'flag' | 'dealbreaker';
  severity: 'soft' | 'medium' | 'high' | 'hard';
  message: string;
}

export interface CalculatorResult {
  overallScore: number | null;
  ceilingApplied: boolean;
  breakdown: QuestionCompatibilityBreakdown[];
  flags: PsychologyCompatibilityFlag[];
  skippedQuestionIds: string[];
}

/**
 * Pure, deterministic scorer. No DB access, no I/O — given a quiz's
 * questions and two users' raw answer maps, returns the per-question
 * breakdown, the overall score (with the Q9 hard-axis ceiling applied if
 * triggered), and every flag (read live from each question's own
 * `pairRules`, plus the two cross-question rules). Calling this twice with
 * the same inputs always returns an equal result — nothing here reads the
 * clock, RNG, or external state.
 */
export function calculatePsychologyCompatibility(
  questions: QuizQuestion[],
  answersA: Record<string, string>,
  answersB: Record<string, string>,
): CalculatorResult {
  const breakdown: QuestionCompatibilityBreakdown[] = [];
  const flags: PsychologyCompatibilityFlag[] = [];
  const skippedQuestionIds: string[] = [];

  // Keyed by dimension so the two cross-question rules can look a specific
  // question's outcome back up after the main loop.
  const breakdownByDimension = new Map<
    string,
    QuestionCompatibilityBreakdown
  >();
  const pairRuleFlagByDimension = new Map<
    string,
    { severity: RawPairRule['severity']; message: string }
  >();

  for (const question of [...questions].sort((a, b) => a.order - b.order)) {
    const keyA = answersA[question.id];
    const keyB = answersB[question.id];

    if (!keyA || !keyB) {
      // Defensive only — submit-time validation already requires every
      // question to be answered, so a stored response shouldn't be able to
      // reach this state. Skip rather than throw, so one malformed question
      // doesn't blank the whole comparison.
      skippedQuestionIds.push(question.id);
      continue;
    }

    const matrix = PSYCHOLOGY_COMPATIBILITY_MATRIX[question.id];
    const score = matrix?.[pairLookupKey(keyA, keyB)];
    if (matrix === undefined || score === undefined) {
      // Unknown question id or option key — the caller (the service) is
      // responsible for verifying quiz-version support before calling this;
      // treat as unscoreable rather than silently defaulting.
      skippedQuestionIds.push(question.id);
      continue;
    }

    const entry: QuestionCompatibilityBreakdown = {
      questionId: question.id,
      dimension: question.dimension,
      score,
      userASelectedKey: keyA,
      userBSelectedKey: keyB,
    };
    breakdown.push(entry);
    breakdownByDimension.set(question.dimension, entry);

    const pairRules = (question.pairRules ?? []) as unknown as RawPairRule[];
    const sortedInput = [keyA, keyB].sort();
    const matchedRule = pairRules.find((rule) => {
      const sortedRule = [...rule.pair].sort();
      return (
        sortedRule[0] === sortedInput[0] && sortedRule[1] === sortedInput[1]
      );
    });

    if (matchedRule) {
      pairRuleFlagByDimension.set(question.dimension, {
        severity: matchedRule.severity,
        message: matchedRule.message,
      });
      flags.push({
        questionId: question.id,
        dimension: question.dimension,
        severity: matchedRule.severity,
        message: matchedRule.message,
        source: 'pairRule',
      });
    }
  }

  // --- Cross-question rule 1: Q10 <-> Q9 escalation -----------------------
  // "Q9 indicates a meaningful children/timeline conflict" is read here as
  // "Q9's own answer pair matched ANY of its pairRules entries" (soft or
  // hard) — i.e. Q9 itself produced a flag. This is the one interpretive
  // call in this engine; flagged explicitly in the Step-4 report for review.
  const q10Flag = pairRuleFlagByDimension.get(ESCALATION_TARGET_DIMENSION);
  const q9Flag = pairRuleFlagByDimension.get(HARD_AXIS_CEILING_DIMENSION);
  if (q10Flag && q9Flag) {
    const escalatedFlag = flags.find(
      (f) =>
        f.dimension === ESCALATION_TARGET_DIMENSION && f.source === 'pairRule',
    );
    if (escalatedFlag) {
      escalatedFlag.severity = 'high';
      escalatedFlag.message = `${escalatedFlag.message} (escalated: the children/timeline question also shows a mismatch)`;
    }
  }

  // --- Cross-question rule 2: Q8 "involve families" <-> Q3 ----------------
  // Informational only, per the approved decision — never changes Q8's or
  // Q3's score, never introduces a new severity/dealbreaker. Triggers when
  // either partner chose Q8's "involve our families" option, regardless of
  // their Q3 answers (both are surfaced so the pair can read them together).
  const decisionEntry = breakdownByDimension.get(
    FAMILY_INVOLVEMENT_DECISION_DIMENSION,
  );
  const involvesFamilies =
    decisionEntry &&
    (decisionEntry.userASelectedKey === FAMILY_INVOLVEMENT_DECISION_KEY ||
      decisionEntry.userBSelectedKey === FAMILY_INVOLVEMENT_DECISION_KEY);
  if (
    involvesFamilies &&
    breakdownByDimension.has(FAMILY_BOUNDARIES_DIMENSION)
  ) {
    flags.push({
      questionId: null,
      dimension: null,
      // Deliberately no `severity` — this is a discussion-only cross
      // reference, never a compatibility-risk severity and never a
      // dealbreaker. `source: 'informational'` is what a consumer should
      // key off of to render this differently from a real flag.
      message:
        'One or both of you would want to involve your families in major decisions — worth discussing this alongside your expectations about family involvement day-to-day.',
      source: 'informational',
    });
  }

  // --- Overall score + Q9 hard-axis ceiling --------------------------------
  const overallScore =
    breakdown.length === 0
      ? null
      : Math.round(
          breakdown.reduce((sum, b) => sum + b.score, 0) / breakdown.length,
        );

  // Reuses the score already computed for Q9 in the main loop above — no
  // second matrix lookup. The dealbreaker pairs (A,D)/(B,D) are the only
  // ones in the approved Q9 matrix scored 0, so "score === 0" is exactly
  // "this pair is the hard-axis dealbreaker."
  const hardAxisEntry = breakdownByDimension.get(HARD_AXIS_CEILING_DIMENSION);
  const hardAxisTriggered = hardAxisEntry?.score === 0;

  const ceilingApplied =
    hardAxisTriggered &&
    overallScore !== null &&
    overallScore > HARD_AXIS_CEILING;
  const finalScore =
    overallScore === null
      ? null
      : ceilingApplied
        ? HARD_AXIS_CEILING
        : overallScore;

  return {
    overallScore: finalScore,
    ceilingApplied,
    breakdown,
    flags,
    skippedQuestionIds,
  };
}
