import type { PreferenceFilters } from '../filters/partner-preference-where.builder';
import type { QuizQuestion } from '../../../../../../libs/database/generated/client';
import { MATCHING_WEIGHTS, type ScoreKey } from './matching-weights.config';

/**
 * The attributes of one person that scoring reads. Deliberately a plain shape
 * rather than a Prisma row: it keeps every signal a pure function of its
 * inputs, so it needs no database, no mocks, and can be unit-tested against
 * hand-written objects.
 */
export interface ScorableProfile {
  userId: string;
  dob: Date | null;
  heightCm: number | null;
  religion: string | null;
  caste: string | null;
  community: string | null;
  motherTongue: string | null;
  highestEducation: string | null;
  profession: string | null;
  currentCity: string | null;
  currentState: string | null;
  maritalStatus: string | null;
  dietaryHabits: string | null;
  smokingHabits: string | null;
  drinkingHabits: string | null;
  profileCompletePct: number | null;
  /** User.trustScore, 0-100. */
  trustScore: number | null;
  /** Proxy for activity — see ACTIVITY_NOTE in the weights config. */
  updatedAt: Date | null;
  /** The candidate's own saved preference, needed for the mutual direction. */
  preference: PreferenceFilters | null;
  /**
   * This person's raw answers to the CURRENT active psychology quiz
   * (`{ questionId: selectedOptionKey }`), if they've completed it.
   * Undefined/null on every ScorableProfile built today — nothing populates
   * this field yet (see psychology-compatibility.signal.ts), which is what
   * keeps that signal inapplicable, and therefore this addition a no-op,
   * until a separate, later step wires real data in.
   */
  psychologyAnswers?: Record<string, string> | null;
}

/** One dimension's contribution, kept so the score can be explained. */
export interface ScoreComponent {
  key: ScoreKey;
  /** 0-1 before weighting. */
  ratio: number;
  weight: number;
  /** ratio × weight. */
  points: number;
  /** False when neither side stated anything — excluded from the total. */
  applicable: boolean;
}

/**
 * One direction of one pairing: how well [candidate] fits [chooser]'s
 * [preference].
 *
 * The two people are never interchangeable. [preference] is what the chooser
 * WANTS in a partner; it is compared against the CANDIDATE's own attributes.
 * The chooser's own attributes are read for one thing only — resolving a
 * relative preference such as "Same Caste" to the chooser's caste. The mutual
 * direction of the score is this same input with the roles swapped, never a
 * second code path.
 */
export interface CompatibilityInput {
  chooser: ScorableProfile;
  preference: PreferenceFilters | null;
  candidate: ScorableProfile;
  /**
   * The current active psychology quiz's questions (with their `pairRules`),
   * shared context rather than a per-profile attribute. Undefined unless the
   * caller explicitly supplies it via CompatibilityService.score()'s optional
   * fourth argument — see that method's doc comment.
   */
  psychologyQuestions?: readonly QuizQuestion[];
}

/**
 * A source of score components.
 *
 * `compatibility` signals describe the PAIR — does this candidate fit what
 * this chooser asked for. They are what `matchedPreferences` and
 * `unmatchedPreferences` explain. Partner preferences are one;
 * psychology-compatibility.signal.ts (the marriage-compatibility quiz,
 * pairwise) is another. A horoscope signal would be a third, not yet built.
 *
 * `quality` signals describe the CANDIDATE alone, whoever is looking —
 * completeness, trust, activity. Verification results belong here.
 *
 * Signals never filter. A candidate reaching them has already passed hard
 * eligibility (filters/eligibility.builder.ts); a signal only contributes
 * components to a weighted average that decides order.
 */
export interface CompatibilitySignal {
  readonly key: string;
  readonly kind: 'compatibility' | 'quality';
  /** The ScoreKeys this signal emits, in the order it emits them. */
  readonly keys: readonly ScoreKey[];
  components(input: CompatibilityInput): ScoreComponent[];
}

/**
 * Builds one component from a raw 0-1 ratio: clamps it, weights it from
 * MATCHING_WEIGHTS, and zeroes an inapplicable one so it can never contribute
 * points while being excluded from the denominator.
 */
export function scoreComponent(
  key: ScoreKey,
  ratio: number,
  applicable: boolean,
): ScoreComponent {
  const weight = MATCHING_WEIGHTS[key];
  const clamped = Math.max(0, Math.min(1, ratio));
  return {
    key,
    ratio: applicable ? clamped : 0,
    weight,
    points: applicable ? clamped * weight : 0,
    applicable,
  };
}
