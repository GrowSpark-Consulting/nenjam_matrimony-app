import { HttpException, HttpStatus } from '@nestjs/common';
import type { StoredObjectFormat } from '@app/storage';

/**
 * AWS discards a Face Liveness session — id, results, reference image — three
 * minutes after CreateFaceLivenessSession. An attempt that is not completed
 * inside this window can only end as EXPIRED.
 */
export const LIVENESS_SESSION_LIFETIME_MS = 3 * 60 * 1000;

/**
 * How long a /complete request may hold an attempt in PROCESSING after the
 * session window closed before the attempt is treated as abandoned (e.g. the
 * process died mid-request) and closed as ERROR.
 */
export const PROCESSING_GRACE_MS = 60 * 1000;

/** Rolling window for the per-member attempt cap. */
export const USER_ATTEMPT_WINDOW_MS = 24 * 60 * 60 * 1000;

/**
 * The only formats CompareFaces accepts. Profile photos may legitimately be
 * WebP (PhotoFilePipe allows it), so this is checked on the real bytes before
 * any paid AWS call — never assumed from the upload's declared type.
 */
export const COMPARE_FACES_FORMATS: readonly StoredObjectFormat[] = [
  'jpeg',
  'png',
];

/** Rekognition's ceiling for inline image bytes. */
export const COMPARE_FACES_MAX_BYTES = 5 * 1024 * 1024;

/**
 * The single action the device's temporary credentials may perform:
 * streaming video into a session the backend already created. Passed as the
 * AssumeRole session policy, so even if the client role were ever granted
 * more, the credentials handed to a device cannot exceed this.
 */
export const LIVENESS_CLIENT_SESSION_POLICY = {
  Version: '2012-10-17',
  Statement: [
    {
      Effect: 'Allow',
      Action: ['rekognition:StartFaceLivenessSession'],
      Resource: '*',
    },
  ],
} as const;

/** Machine-readable error codes, returned as `code` beside Nest's `message`. */
export const FaceVerificationErrorCode = {
  NOT_AVAILABLE: 'NOT_AVAILABLE',
  ALREADY_VERIFIED: 'ALREADY_VERIFIED',
  NO_PRIMARY_PHOTO: 'NO_PRIMARY_PHOTO',
  UNSUPPORTED_PHOTO: 'UNSUPPORTED_PHOTO',
  ATTEMPT_LIMIT: 'ATTEMPT_LIMIT',
  ATTEMPT_NOT_FOUND: 'ATTEMPT_NOT_FOUND',
  ATTEMPT_IN_PROGRESS: 'ATTEMPT_IN_PROGRESS',
  RESULT_NOT_READY: 'RESULT_NOT_READY',
  PROVIDER_UNAVAILABLE: 'PROVIDER_UNAVAILABLE',
} as const;

export type FaceVerificationErrorCode =
  (typeof FaceVerificationErrorCode)[keyof typeof FaceVerificationErrorCode];

/**
 * Builds a standard Nest HttpException whose body keeps Nest's usual
 * `{ statusCode, message }` shape and adds `code` (plus any extra fields such
 * as `retryAfter`), so the client can branch on a stable value instead of
 * parsing human-readable text. A plain HttpException, not a new exception
 * class — the codebase deliberately has no custom exception hierarchy.
 */
export function faceVerificationError(
  status: HttpStatus,
  code: FaceVerificationErrorCode,
  message: string,
  extra: Record<string, unknown> = {},
): HttpException {
  return new HttpException(
    { statusCode: status, code, message, ...extra },
    status,
  );
}
