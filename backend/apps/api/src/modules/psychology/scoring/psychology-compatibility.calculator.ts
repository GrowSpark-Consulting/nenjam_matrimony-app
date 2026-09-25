import {
  PSYCHOLOGY_COMPATIBILITY_MATRIX,
  pairLookupKey,
} from './compatibility-matrix.data';
import {
  answerFor,
  parsePairRules,
  type RawPairRule,
} from './psychology-data.guards';
import type {
  PsychologyCompatibilityFlag,
  QuestionCompatibilityBreakdown,
  ScoringQuestion,
} from './psychology-compatibility.types';

const HARD_AXIS_CEILING = 40;

// Q10's dimension — the question whose (B,D)/(C,D) flag escalates when the
// hard-axis question (Q9) shows a meaningful conflict.
export const ESCALATION_TARGET_DIMENSION = 'life_stage_timeline';

// Q8's dimension — the question whose "D" (involve families) option gets an
// informational, score-neutral cross-check note against Q3.
export const FAMILY_INVOLVEMENT_DECISION_DIMENSION = 'decision_making';
export const FAMILY_INVOLVEMENT_DECISION_KEY = 'D';
export const FAMILY_BOUNDARIES_DIMENSION = 'family_boundaries';

const SEVERITY_RANK: Record<RawPairRule['severity'], number> = {
  soft: 1,
  medium: 2,
  high: 3,
  hard: 4,
};

export interface CalculatorResult {
  overallScore: number | null;
  ceilingApplied: boolean;
  breakdown: QuestionCompatibilityBreakdown[];
  flags: PsychologyCompatibilityFlag[];
  skippedQuestionIds: string[];
  /**
   * The pair gave the hard-axis question's dealbreaker combination (its
   * matrix score is 0). Independent of the overall score — the ceiling only
   * bites when the average was above it, this is true either way.
   */
  hardAxisConflict: boolean;
  /**
   * True only when EVERY supplied question was scored (and there was at least
   * one). A pair that is not `complete` has a score computed from a subset of
   * the quiz — and, if the skipped subset includes the hard-axis question, one
   * that silently missed the dealbreaker ceiling — so consumers that rank
   * with it must treat it as "no psychology score", not as a score.
   */
  complete: boolean;
}

export interface CalculatorOptions {
  /**
   * When false, skips pair-rule matching and the cross-question rules and
   * returns `flags: []`. The score and ceiling are unaffected. Discover only
   * consumes the score, so it opts out and never has to read `pairRules`.
   * Defaults to true.
   */
  includeFlags?: boolean;
}

type StoredAnswers = Readonly<Record<string, unknown>> | null | undefined;

/**
 * Pure, deterministic scorer. No DB access, no I/O — given a quiz's
 * questions and two users' raw answer maps, returns the per-question
 * breakdown, the overall score (with the hard-axis ceiling applied if
 * triggered), and every flag (read live from each question's own
 * `pairRules`, plus the two cross-question rules). Calling this twice with
 * the same inputs always returns an equal result — nothing here reads the
 * clock, RNG, or external state.
 *
 * It never throws on malformed stored data: answers that aren't an object
 * read as unanswered, and malformed pair rules are ignored. This runs inside
 * every Discover request, where an exception would take the whole feed down.
 */
export function calculatePsychologyCompatibility(
  questions: readonly ScoringQuestion[],
  answersA: StoredAnswers,
  answersB: StoredAnswers,
  options: CalculatorOptions = {},
): CalculatorResult {
  const includeFlags = options.includeFlags !== false;
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
    PsychologyCompatibilityFlag
  >();

  // The hard-axis question is identified by its stored scoringType, not by a
  // hardcoded dimension name, so renaming a dimension can't silently disable
  // the ceiling.
  let hardAxisTriggered = false;
  let hardAxisFlagRank = 0;

  for (const question of [...questions].sort((a, b) => a.order - b.order)) {
    const keyA = answerFor(answersA, question.id);
    const keyB = answerFor(answersB, question.id);

    if (keyA === undefined || keyB === undefined) {
      // A stored response can lack an answer (a question added after it was
      // submitted, or malformed data). Skip rather than throw, so one bad
      // question doesn't blank the whole comparison — the caller decides,
      // via `complete`, whether a partial comparison is usable.
      skippedQuestionIds.push(question.id);
      continue;
    }

    // Own-property lookups: an id or key such as "constructor" must never
    // resolve to something inherited from Object.prototype.
    const matrix = Object.prototype.hasOwnProperty.call(
      PSYCHOLOGY_COMPATIBILITY_MATRIX,
      question.id,
    )
      ? PSYCHOLOGY_COMPATIBILITY_MATRIX[question.id]
      : undefined;
    const cell = pairLookupKey(keyA, keyB);
    const score =
      matrix !== undefined && Object.prototype.hasOwnProperty.call(matrix, cell)
        ? matrix[cell]
        : undefined;
    if (score === undefined) {
      // Unknown question id or option key — treat as unscoreable rather than
      // silently defaulting.
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

    // The dealbreaker pairs (A,D)/(B,D) are the only ones in the approved
    // hard-axis matrix scored 0, so "score === 0" is exactly "this pair is the
    // hard-axis dealbreaker".
    const isHardAxis = question.scoringType === 'HARD_AXIS';
    if (isHardAxis && score === 0) hardAxisTriggered = true;

    if (!includeFlags) continue;

    const sortedInput = [keyA, keyB].sort();
    const matchedRule = parsePairRules(question.pairRules).find((rule) => {
      const sortedRule = [...rule.pair].sort();
      return (
        sortedRule[0] === sortedInput[0] && sortedRule[1] === sortedInput[1]
      );
    });

    if (matchedRule) {
      const flag: PsychologyCompatibilityFlag = {
        questionId: question.id,
        dimension: question.dimension,
        severity: matchedRule.severity,
        message: matchedRule.message,
        source: 'pairRule',
      };
      pairRuleFlagByDimension.set(question.dimension, flag);
      if (isHardAxis) hardAxisFlagRank = SEVERITY_RANK[matchedRule.severity];
      flags.push(flag);
    }
  }

  if (includeFlags) {
    // --- Cross-question rule 1: Q10 <-> Q9 escalation ---------------------
    // "Q9 indicates a meaningful children/timeline conflict" is read as "the
    // hard-axis question's own answer pair matched a rule of at least MEDIUM
    // severity". A soft Q9 flag ("open either way" vs "want children soon" —
    // just 'set a timeline for this conversation') is not a meaningful
    // conflict and no longer escalates Q10. Escalation only ever RAISES a
    // severity to 'high' — it never lowers a flag that is already higher.
    const q10Flag = pairRuleFlagByDimension.get(ESCALATION_TARGET_DIMENSION);
    if (q10Flag && hardAxisFlagRank >= SEVERITY_RANK.medium) {
      if (SEVERITY_RANK[q10Flag.severity!] < SEVERITY_RANK.high) {
        q10Flag.severity = 'high';
      }
      q10Flag.message = `${q10Flag.message} (escalated: the children/timeline question also shows a mismatch)`;
    }

    // --- Cross-question rule 2: Q8 "involve families" <-> Q3 --------------
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
  }

  // --- Overall score + hard-axis ceiling -----------------------------------
  const overallScore =
    breakdown.length === 0
      ? null
      : Math.round(
          breakdown.reduce((sum, b) => sum + b.score, 0) / breakdown.length,
        );

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
    hardAxisConflict: hardAxisTriggered,
    complete:
      questions.length > 0 &&
      skippedQuestionIds.length === 0 &&
      breakdown.length === questions.length,
  };
}
