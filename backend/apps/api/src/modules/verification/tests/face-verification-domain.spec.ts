import {
  faceVerificationDisplayStatus,
  isFaceVerified,
  primaryPhotoOf,
  type StoredFaceVerification,
} from '../domain/face-verification-state';
import {
  evaluateLiveness,
  evaluateMatch,
} from '../domain/face-verification-decision';

const PRIMARY = { id: 'photo-1', s3Key: 'profile-photos/u1/a.jpg' };
const VERIFIED: StoredFaceVerification = {
  status: 'VERIFIED',
  matchedPhotoId: 'photo-1',
  matchedPhotoS3Key: 'profile-photos/u1/a.jpg',
  revokedAt: null,
};

describe('face verification state derivation', () => {
  it('is verified only while the matched photo is still the primary photo', () => {
    expect(isFaceVerified(VERIFIED, PRIMARY)).toBe(true);
  });

  it('ends when the matched photo is replaced (same id, new object)', () => {
    expect(
      isFaceVerified(VERIFIED, {
        id: 'photo-1',
        s3Key: 'profile-photos/u1/b.jpg',
      }),
    ).toBe(false);
  });

  it('ends when another photo becomes primary', () => {
    expect(
      isFaceVerified(VERIFIED, {
        id: 'photo-2',
        s3Key: 'profile-photos/u1/c.jpg',
      }),
    ).toBe(false);
  });

  it('ends when the matched photo is deleted (FK nulled) or no primary exists', () => {
    expect(isFaceVerified({ ...VERIFIED, matchedPhotoId: null }, PRIMARY)).toBe(
      false,
    );
    expect(isFaceVerified(VERIFIED, null)).toBe(false);
  });

  it('is never verified when unverified, revoked, or absent', () => {
    expect(isFaceVerified({ ...VERIFIED, status: 'UNVERIFIED' }, PRIMARY)).toBe(
      false,
    );
    expect(isFaceVerified({ ...VERIFIED, status: 'REVOKED' }, PRIMARY)).toBe(
      false,
    );
    expect(
      isFaceVerified({ ...VERIFIED, revokedAt: new Date() }, PRIMARY),
    ).toBe(false);
    expect(isFaceVerified(null, PRIMARY)).toBe(false);
    expect(isFaceVerified(undefined, PRIMARY)).toBe(false);
  });

  it('reports a verification that no longer holds as REVOKED', () => {
    expect(faceVerificationDisplayStatus(VERIFIED, PRIMARY)).toBe('VERIFIED');
    expect(faceVerificationDisplayStatus(VERIFIED, null)).toBe('REVOKED');
    expect(
      faceVerificationDisplayStatus(
        { ...VERIFIED, status: 'REVOKED' },
        PRIMARY,
      ),
    ).toBe('REVOKED');
    expect(
      faceVerificationDisplayStatus(
        { ...VERIFIED, status: 'UNVERIFIED' },
        PRIMARY,
      ),
    ).toBe('UNVERIFIED');
    expect(faceVerificationDisplayStatus(null, PRIMARY)).toBe('UNVERIFIED');
  });

  it('only treats a photo flagged primary as the primary photo', () => {
    expect(
      primaryPhotoOf([
        { id: 'a', s3Key: 'k-a', isPrimary: false },
        { id: 'b', s3Key: 'k-b', isPrimary: true },
      ]),
    ).toEqual({ id: 'b', s3Key: 'k-b' });
    // Legacy rows with no primary never fall back to the first photo.
    expect(
      primaryPhotoOf([{ id: 'a', s3Key: 'k-a', isPrimary: false }]),
    ).toBeNull();
    expect(primaryPhotoOf([{ s3Key: 'k-a', isPrimary: true }])).toBeNull();
    expect(primaryPhotoOf([])).toBeNull();
  });
});

describe('evaluateLiveness', () => {
  const pass = {
    status: 'SUCCEEDED',
    confidence: 97.5,
    hasReferenceImage: true,
  };

  it('passes a succeeded session at or above the threshold with a reference image', () => {
    expect(evaluateLiveness(pass, 90)).toBeNull();
    expect(evaluateLiveness({ ...pass, confidence: 90 }, 90)).toBeNull();
  });

  it('fails below the threshold, or with no/invalid confidence', () => {
    expect(evaluateLiveness({ ...pass, confidence: 89.99 }, 90)).toBe(
      'FAILED_LIVENESS',
    );
    expect(evaluateLiveness({ ...pass, confidence: undefined }, 90)).toBe(
      'FAILED_LIVENESS',
    );
    expect(evaluateLiveness({ ...pass, confidence: NaN }, 90)).toBe(
      'FAILED_LIVENESS',
    );
  });

  it('fails any status other than SUCCEEDED, mapping EXPIRED separately', () => {
    expect(evaluateLiveness({ ...pass, status: 'FAILED' }, 90)).toBe(
      'FAILED_LIVENESS',
    );
    expect(evaluateLiveness({ ...pass, status: 'UNKNOWN' }, 90)).toBe(
      'FAILED_LIVENESS',
    );
    expect(evaluateLiveness({ ...pass, status: 'EXPIRED' }, 90)).toBe(
      'EXPIRED',
    );
  });

  it('requires a reference image to compare against', () => {
    expect(evaluateLiveness({ ...pass, hasReferenceImage: false }, 90)).toBe(
      'NO_REFERENCE_IMAGE',
    );
  });
});

describe('evaluateMatch', () => {
  it('verifies exactly one face at or above the similarity threshold', () => {
    expect(evaluateMatch({ faceCount: 1, bestSimilarity: 99.1 }, 90)).toBe(
      'VERIFIED',
    );
    expect(evaluateMatch({ faceCount: 1, bestSimilarity: 90 }, 90)).toBe(
      'VERIFIED',
    );
  });

  it('rejects a photo with no face or more than one face', () => {
    expect(evaluateMatch({ faceCount: 0 }, 90)).toBe('NO_FACE_IN_PHOTO');
    expect(evaluateMatch({ faceCount: 2, bestSimilarity: 99 }, 90)).toBe(
      'MULTIPLE_FACES_IN_PHOTO',
    );
  });

  it('fails a match below the threshold or without a similarity', () => {
    expect(evaluateMatch({ faceCount: 1, bestSimilarity: 89.9 }, 90)).toBe(
      'FAILED_MATCH',
    );
    expect(evaluateMatch({ faceCount: 1 }, 90)).toBe('FAILED_MATCH');
  });
});
