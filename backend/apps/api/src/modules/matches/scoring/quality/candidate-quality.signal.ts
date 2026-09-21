import {
  scoreComponent,
  type CompatibilityInput,
  type CompatibilitySignal,
} from '../compatibility-signal';
import { ACTIVITY_DECAY_DAYS } from '../matching-weights.config';

const MS_PER_DAY = 86_400_000;

/**
 * Facts about the candidate alone — the same whoever is looking. Always
 * applicable except activity, which has nothing to say without a timestamp.
 *
 * Verification is read from `User.trustScore` and nothing else. When real
 * identity/selfie/education/income/employment checks exist, they should feed
 * that score (or add a component here) rather than reach into ranking.
 */
export const CANDIDATE_QUALITY_SIGNAL: CompatibilitySignal = {
  key: 'candidateQuality',
  kind: 'quality',
  keys: ['profileCompleteness', 'verification', 'activity'],
  components({ candidate }: CompatibilityInput) {
    return [
      // Complete profiles convert better; this rewards finishing the wizard.
      scoreComponent(
        'profileCompleteness',
        (candidate.profileCompletePct ?? 0) / 100,
        true,
      ),
      scoreComponent('verification', (candidate.trustScore ?? 0) / 100, true),
      activityComponent(candidate.updatedAt),
    ];
  },
};

/** Linear decay to zero over ACTIVITY_DECAY_DAYS. Proxy data — see the note. */
function activityComponent(updatedAt: Date | null) {
  if (!updatedAt) return scoreComponent('activity', 0, false);
  const days = (Date.now() - updatedAt.getTime()) / MS_PER_DAY;
  return scoreComponent('activity', 1 - days / ACTIVITY_DECAY_DAYS, true);
}
