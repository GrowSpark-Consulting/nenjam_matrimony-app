/**
 * Read-time derivation of the "Face Verified" badge.
 *
 * Shared by the verification endpoints and ProfileFeedMapper (every profile
 * card: feed, search, nearby, profile views, shortlist, interests, chat,
 * blocks), so there is exactly one definition of "verified".
 *
 * A verification vouches for ONE photo: the primary photo the live selfie was
 * matched against. It holds only while that exact photo is still the member's
 * primary photo. Each photo change ends it without PhotoService knowing face
 * verification exists:
 *   - replace:        same photo id, new s3Key      -> key no longer matches
 *   - delete:         FK SetNull on matchedPhotoId  -> no matched photo
 *   - primary change: isPrimary moves elsewhere     -> primary id differs
 *
 * Plain string unions (not the generated Prisma enums) keep this importable
 * from any mapper without dragging the Prisma client into its type surface.
 */

export interface StoredFaceVerification {
  status: string;
  matchedPhotoId: string | null;
  matchedPhotoS3Key: string | null;
  revokedAt?: Date | null;
}

export interface PrimaryPhotoRef {
  id: string;
  s3Key: string;
}

/** What clients are told. REVOKED = was verified, no longer holds. */
export type FaceVerificationDisplayStatus =
  'UNVERIFIED' | 'VERIFIED' | 'REVOKED';

export function isFaceVerified(
  stored: StoredFaceVerification | null | undefined,
  primary: PrimaryPhotoRef | null | undefined,
): boolean {
  if (!stored || stored.status !== 'VERIFIED' || stored.revokedAt) return false;
  if (!stored.matchedPhotoId || !stored.matchedPhotoS3Key || !primary) {
    return false;
  }
  return (
    primary.id === stored.matchedPhotoId &&
    primary.s3Key === stored.matchedPhotoS3Key
  );
}

export function faceVerificationDisplayStatus(
  stored: StoredFaceVerification | null | undefined,
  primary: PrimaryPhotoRef | null | undefined,
): FaceVerificationDisplayStatus {
  if (isFaceVerified(stored, primary)) return 'VERIFIED';
  if (stored && (stored.status === 'VERIFIED' || stored.status === 'REVOKED')) {
    return 'REVOKED';
  }
  return 'UNVERIFIED';
}

/**
 * The member's primary photo from a photo list. Only a photo actually flagged
 * primary counts — a list with no primary (legacy data) yields null rather
 * than silently treating the first photo as the one that was verified.
 */
export function primaryPhotoOf(
  photos: ReadonlyArray<{ id?: string; s3Key: string; isPrimary?: boolean }>,
): PrimaryPhotoRef | null {
  const primary = photos.find((p) => p.isPrimary === true && p.id);
  return primary && primary.id
    ? { id: primary.id, s3Key: primary.s3Key }
    : null;
}
