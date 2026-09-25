import { PSYCHOLOGY_COMPATIBILITY_MATRIX } from './compatibility-matrix.data';
import type {
  PsychologyFlagSeverity,
  ScoringQuestion,
} from './psychology-compatibility.types';

/**
 * Runtime validation for data that arrives as `Json` from the database.
 *
 * `UserQuizResponse.answers` and `QuizQuestion.pairRules` are typed by cast
 * (`as unknown as Record<...>`), never by the database. Anything that can be
 * written by hand — a seed edit, a manual SQL fix, a future writer — can
 * therefore be `null`, an array, or half a rule. Scoring runs inside every
 * Discover request, so it must degrade to "no psychology score" on such data
 * rather than throw. Everything here returns a safe value instead of throwing.
 */

export interface RawPairRule {
  pair: [string, string];
  type: 'flag' | 'dealbreaker';
  severity: PsychologyFlagSeverity;
  message: string;
}

const SEVERITIES: ReadonlySet<string> = new Set([
  'soft',
  'medium',
  'high',
  'hard',
]);
const RULE_TYPES: ReadonlySet<string> = new Set(['flag', 'dealbreaker']);

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * A user's stored `{ questionId: selectedKey }` map, or null when the stored
 * value isn't an object at all. Non-string values are dropped rather than
 * kept, so a malformed entry can only ever read as "unanswered".
 */
export function parseStoredAnswers(
  raw: unknown,
): Record<string, string> | null {
  if (!isPlainRecord(raw)) return null;
  const out: Record<string, string> = {};
  for (const [questionId, selectedKey] of Object.entries(raw)) {
    if (questionId === '__proto__') continue;
    if (typeof selectedKey === 'string' && selectedKey.length > 0) {
      out[questionId] = selectedKey;
    }
  }
  return out;
}

/** The answer for one question, only if it is an own, non-empty string. */
export function answerFor(
  answers: Readonly<Record<string, unknown>> | null | undefined,
  questionId: string,
): string | undefined {
  if (!isPlainRecord(answers)) return undefined;
  if (!Object.prototype.hasOwnProperty.call(answers, questionId)) {
    return undefined;
  }
  const value = answers[questionId];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

/** Well-formed pair rules only; a malformed entry is dropped, never thrown on. */
export function parsePairRules(raw: unknown): RawPairRule[] {
  if (!Array.isArray(raw)) return [];
  const rules: RawPairRule[] = [];
  for (const entry of raw as unknown[]) {
    if (!isPlainRecord(entry)) continue;
    const { pair, type, severity, message } = entry;
    if (
      Array.isArray(pair) &&
      pair.length === 2 &&
      typeof pair[0] === 'string' &&
      typeof pair[1] === 'string' &&
      typeof type === 'string' &&
      RULE_TYPES.has(type) &&
      typeof severity === 'string' &&
      SEVERITIES.has(severity) &&
      typeof message === 'string'
    ) {
      rules.push({
        pair: [pair[0], pair[1]],
        type: type as RawPairRule['type'],
        severity: severity as PsychologyFlagSeverity,
        message,
      });
    }
  }
  return rules;
}

/**
 * Why a set of questions can't be scored against the approved matrix, or null
 * when it can. This is the single support check: Discover, the standalone
 * compatibility service and the quiz provider all use it, so they can never
 * disagree about whether a quiz is scoreable.
 *
 * All-or-nothing on purpose. Scoring "the questions we happen to recognise"
 * would silently produce a number against a matrix that no longer matches the
 * quiz, and would make scores from different quiz contents incomparable.
 */
export function unsupportedQuizReason(
  questions: readonly ScoringQuestion[],
): string | null {
  if (questions.length === 0) return 'the quiz has no questions';

  const ids = new Set<string>();
  const dimensions = new Set<string>();
  for (const q of questions) {
    if (
      !Object.prototype.hasOwnProperty.call(
        PSYCHOLOGY_COMPATIBILITY_MATRIX,
        q.id,
      )
    ) {
      return `question "${q.id}" has no entry in the approved matrix`;
    }
    if (ids.has(q.id)) return `question "${q.id}" appears twice`;
    if (dimensions.has(q.dimension)) {
      return `dimension "${q.dimension}" is used by more than one question`;
    }
    ids.add(q.id);
    dimensions.add(q.dimension);
  }
  return null;
}

/**
 * Whether a response was given against the quiz content that is active now.
 * A null version (a row from before versions were recorded) counts as current:
 * introducing the column must not invalidate any member's existing answers.
 * A non-null version that differs means the quiz's content was revised under
 * the same id — the response is stale and must be retaken.
 */
export function responseMatchesQuizVersion(
  responseVersion: string | null | undefined,
  quizVersion: string,
): boolean {
  return responseVersion == null || responseVersion === quizVersion;
}

/** Two answer maps are the same when they answer the same questions the same way. */
export function sameAnswers(
  a: Readonly<Record<string, string>> | null,
  b: Readonly<Record<string, string>> | null,
): boolean {
  if (!a || !b) return false;
  const keysA = Object.keys(a);
  if (keysA.length !== Object.keys(b).length) return false;
  return keysA.every(
    (key) => Object.prototype.hasOwnProperty.call(b, key) && a[key] === b[key],
  );
}

/**
 * True when `answers` covers every question with a key that is a valid option
 * for it. Used to tell a current response from one made against older quiz
 * content (a question added, an option key removed).
 */
export function coversQuestions(
  answers: Readonly<Record<string, unknown>> | null | undefined,
  questions: readonly { id: string; options?: unknown }[],
): boolean {
  if (questions.length === 0) return false;
  return questions.every((q) => {
    const key = answerFor(answers, q.id);
    if (key === undefined) return false;
    if (!Array.isArray(q.options)) return true; // options not loaded: coverage only
    return (q.options as unknown[]).some(
      (o) => isPlainRecord(o) && o.key === key,
    );
  });
}
