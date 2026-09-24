import {
  scoreComponent,
  type CompatibilityInput,
  type CompatibilitySignal,
} from '../compatibility-signal';
import { calculatePsychologyCompatibility } from '../../../psychology/scoring/psychology-compatibility.calculator';

/**
 * Pairwise marriage-compatibility-quiz score, reusing the exact same
 * deterministic calculator (approved matrix, Q9 ceiling, Q10<->Q9
 * escalation, Q8-D<->Q3 informational note) that the standalone psychology
 * module uses — there is only ever one scoring implementation, never a
 * second copy kept in sync by hand.
 *
 * Applicable only when BOTH sides have completed the current active quiz
 * (`psychologyAnswers` set on both ScorableProfiles) AND the caller supplied
 * that quiz's questions via CompatibilityInput.psychologyQuestions.
 * Otherwise inapplicable — excluded from the denominator exactly like an
 * unstated partner preference, never scored as a mismatch. This is why
 * adding this signal changes nothing for any pair today: nothing yet
 * populates `psychologyAnswers`/`psychologyQuestions` on a real request.
 *
 * Deliberately does not surface flags (dealbreaker/discussion notes) here —
 * only the 0-100 score. Carrying flags through CompatibilityBreakdown is a
 * separate, later addition once this scoring path is live and proven.
 */
export const PSYCHOLOGY_COMPATIBILITY_SIGNAL: CompatibilitySignal = {
  key: 'psychology',
  kind: 'compatibility',
  keys: ['psychology'],
  components({ chooser, candidate, psychologyQuestions }: CompatibilityInput) {
    const chooserAnswers = chooser.psychologyAnswers;
    const candidateAnswers = candidate.psychologyAnswers;

    if (!chooserAnswers || !candidateAnswers || !psychologyQuestions?.length) {
      return [scoreComponent('psychology', 0, false)];
    }

    const result = calculatePsychologyCompatibility(
      [...psychologyQuestions],
      chooserAnswers,
      candidateAnswers,
    );

    if (result.overallScore === null) {
      // Every question was skipped (malformed/mismatched data) — same
      // "nothing to score" outcome as missing answers entirely.
      return [scoreComponent('psychology', 0, false)];
    }

    return [scoreComponent('psychology', result.overallScore / 100, true)];
  },
};
