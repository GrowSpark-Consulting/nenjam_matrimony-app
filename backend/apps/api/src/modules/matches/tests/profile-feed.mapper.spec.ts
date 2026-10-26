import type { S3Service } from '@app/storage';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import type { FeedProfileRow } from '../repositories/feed.repository';

// Focused on the face-verification badge. ProfileFeedMapper backs every
// profile card (feed, search, nearby, profile views, shortlist, interests,
// chat, blocks) through the shared FEED_PROFILE_SELECT, so this one mapping
// is what keeps the badge consistent everywhere.
const s3 = { isConfigured: () => false } as unknown as S3Service;

const PRIMARY = {
  id: 'photo-1',
  s3Key: 'profile-photos/u1/a.jpg',
  isPrimary: true,
};
const OTHER = {
  id: 'photo-2',
  s3Key: 'profile-photos/u1/b.jpg',
  isPrimary: false,
};
const VERIFIED = {
  status: 'VERIFIED',
  matchedPhotoId: 'photo-1',
  matchedPhotoS3Key: 'profile-photos/u1/a.jpg',
  revokedAt: null,
};

function row(user: Record<string, unknown>): FeedProfileRow {
  return { userId: 'u1', firstName: 'A', lastName: 'B', user };
}

describe('ProfileFeedMapper isVerified', () => {
  const mapper = new ProfileFeedMapper(s3);

  it('is true while the matched photo is the current primary photo', async () => {
    const dto = await mapper.toDto(
      row({ photos: [PRIMARY, OTHER], faceVerification: VERIFIED }),
    );
    expect(dto.isVerified).toBe(true);
  });

  it('is false once another photo is primary', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [
          { ...OTHER, isPrimary: true },
          { ...PRIMARY, isPrimary: false },
        ],
        faceVerification: VERIFIED,
      }),
    );
    expect(dto.isVerified).toBe(false);
  });

  it('is false once the matched photo was replaced (same id, new object)', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [{ ...PRIMARY, s3Key: 'profile-photos/u1/new.jpg' }],
        faceVerification: VERIFIED,
      }),
    );
    expect(dto.isVerified).toBe(false);
  });

  it('is false once the matched photo was deleted', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [{ ...OTHER, isPrimary: true }],
        faceVerification: { ...VERIFIED, matchedPhotoId: null },
      }),
    );
    expect(dto.isVerified).toBe(false);
  });

  it('is false for unverified, revoked, or missing state', async () => {
    for (const faceVerification of [
      null,
      undefined,
      { ...VERIFIED, status: 'UNVERIFIED' },
      { ...VERIFIED, status: 'REVOKED' },
      { ...VERIFIED, revokedAt: new Date() },
    ]) {
      const dto = await mapper.toDto(
        row({ photos: [PRIMARY], faceVerification }),
      );
      expect(dto.isVerified).toBe(false);
    }
  });

  it('is false for a row selected without user/photo data', async () => {
    const dto = await mapper.toDto({ userId: 'u1' });
    expect(dto.isVerified).toBe(false);
  });
});

describe('ProfileFeedMapper joinedAt', () => {
  const mapper = new ProfileFeedMapper(s3);

  it('is the profile creation time, as ISO 8601', async () => {
    const created = new Date('2026-10-20T08:15:00.000Z');
    const dto = await mapper.toDto({ ...row({}), createdAt: created });
    expect(dto.joinedAt).toBe('2026-10-20T08:15:00.000Z');
  });

  // Never defaulted to "now": that would label every member as new.
  it('is null when the row carries no creation time', async () => {
    expect((await mapper.toDto(row({}))).joinedAt).toBeNull();
    expect(
      (await mapper.toDto({ ...row({}), createdAt: 'not a date' })).joinedAt,
    ).toBeNull();
  });
});
