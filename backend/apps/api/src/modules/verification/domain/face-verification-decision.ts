/**
 * The backend-only verification decision, as pure functions so every rule is
 * unit-testable without AWS or a database. Nothing the device reports feeds
 * into these — only AWS results and configured thresholds.
 */

/** Terminal attempt outcomes these rules can produce. */
export type FaceDecisionOutcome =
  | 'VERIFIED'
  | 'FAILED_LIVENESS'
  | 'FAILED_MATCH'
  | 'NO_FACE_IN_PHOTO'
  | 'MULTIPLE_FACES_IN_PHOTO'
  | 'NO_REFERENCE_IMAGE'
  | 'EXPIRED';

export interface LivenessEvidence {
  /** Raw AWS session status. */
  status: string;
  confidence?: number;
  hasReferenceImage: boolean;
}

export interface MatchEvidence {
  /** Faces CompareFaces found in the profile photo (target image). */
  faceCount: number;
  /** Best similarity against the liveness reference face, 0-100. */
  bestSimilarity?: number;
}

/**
 * Null when liveness passed and face matching may proceed; otherwise the
 * outcome that ends the attempt. Callers handle the non-terminal AWS states
 * (CREATED / IN_PROGRESS) before calling this.
 */
export function evaluateLiveness(
  evidence: LivenessEvidence,
  minConfidence: number,
): FaceDecisionOutcome | null {
  if (evidence.status === 'EXPIRED') return 'EXPIRED';
  if (evidence.status !== 'SUCCEEDED') return 'FAILED_LIVENESS';
  if (
    typeof evidence.confidence !== 'number' ||
    !Number.isFinite(evidence.confidence) ||
    evidence.confidence < minConfidence
  ) {
    return 'FAILED_LIVENESS';
  }
  // AWS: "In case the reference image is not returned, it's recommended to
  // retry the Liveness check." Without it there is nothing to compare.
  if (!evidence.hasReferenceImage) return 'NO_REFERENCE_IMAGE';
  return null;
}

/**
 * The profile photo must show exactly one face, and it must be the live face.
 * Requiring one face stops a group photo from verifying because someone in it
 * resembles the person taking the selfie.
 */
export function evaluateMatch(
  evidence: MatchEvidence,
  minSimilarity: number,
): FaceDecisionOutcome {
  if (evidence.faceCount <= 0) return 'NO_FACE_IN_PHOTO';
  if (evidence.faceCount > 1) return 'MULTIPLE_FACES_IN_PHOTO';
  if (
    typeof evidence.bestSimilarity !== 'number' ||
    !Number.isFinite(evidence.bestSimilarity) ||
    evidence.bestSimilarity < minSimilarity
  ) {
    return 'FAILED_MATCH';
  }
  return 'VERIFIED';
}
