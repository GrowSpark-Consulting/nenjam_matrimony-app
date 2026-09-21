/**
 * The seam between face verification and AWS. FaceVerificationService depends
 * only on this interface (injected under FACE_LIVENESS_GATEWAY), so the whole
 * flow — decisions, caps, idempotency, persistence — is testable with a fake
 * and never touches the network in tests. AwsFaceLivenessGateway is the one
 * real implementation.
 *
 * Methods throw the underlying AWS SDK error on failure; callers classify it
 * by name with [awsErrorName].
 */

export const FACE_LIVENESS_GATEWAY = Symbol('FACE_LIVENESS_GATEWAY');

export interface LivenessSessionResult {
  /** Raw AWS status: CREATED | IN_PROGRESS | SUCCEEDED | FAILED | EXPIRED. */
  status: string;
  /** Liveness confidence, 0-100. */
  confidence?: number;
  /** High-quality frame from the selfie video, held in memory only. */
  referenceImage?: Uint8Array;
}

export interface CompareFacesResult {
  /** Faces detected in the target (profile) image. */
  faceCount: number;
  /** Highest similarity between the source face and a target face, 0-100. */
  bestSimilarity?: number;
}

/** Short-lived credentials for the device. Never logged, never persisted. */
export interface TemporaryAwsCredentials {
  accessKeyId: string;
  secretAccessKey: string;
  sessionToken: string;
  expiration: Date;
}

export interface FaceLivenessGateway {
  /** True only when every AWS value the gateway needs is configured. */
  isConfigured(): boolean;
  /** The configured AWS region the device must stream to. */
  region(): string;
  /** Returns the new session id. `clientRequestToken` makes it idempotent. */
  createLivenessSession(clientRequestToken: string): Promise<string>;
  getLivenessSessionResults(sessionId: string): Promise<LivenessSessionResult>;
  compareFaces(
    source: Uint8Array,
    target: Uint8Array,
  ): Promise<CompareFacesResult>;
  /** STS credentials scoped to rekognition:StartFaceLivenessSession only. */
  issueClientCredentials(sessionName: string): Promise<TemporaryAwsCredentials>;
}

/** The AWS SDK error name (e.g. "SessionNotFoundException"), or "Error". */
export function awsErrorName(error: unknown): string {
  const name = (error as { name?: unknown } | null)?.name;
  return typeof name === 'string' && name.length > 0 ? name : 'Error';
}
