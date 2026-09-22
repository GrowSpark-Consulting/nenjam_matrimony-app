import type { S3Service } from '@app/storage';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import {
  feedProfileSelectFor,
  type FeedProfileRow,
} from '../repositories/feed.repository';

/**
 * "Hide my photos from people I'm not connected with" — a setting members
 * could already switch on, which nothing enforced: the feed signed and
 * returned their photo URLs to every viewer regardless.
 *
 * Enforced in the mapper, which backs EVERY profile card (feed, search, near
 * me, profile views, shortlist, interests, chat, blocks), and fed by
 * `feedProfileSelectFor(viewerId)`, which asks the database whether this
 * particular viewer is connected. A connection is an accepted interest in
 * either direction — the app's own definition of a match.
 */
const s3 = {
  isConfigured: () => true,
  getPresignedGetUrl: (key: string) => Promise.resolve(`https://signed/${key}`),
} as unknown as S3Service;

const PHOTO = { id: 'photo-1', s3Key: 'u1/a.jpg', isPrimary: true };

function row(user: Record<string, unknown>): FeedProfileRow {
  return { userId: 'u1', firstName: 'A', lastName: 'B', user };
}

describe('photo privacy', () => {
  const mapper = new ProfileFeedMapper(s3);

  it('serves photos when the member has not asked to hide them', async () => {
    const dto = await mapper.toDto(
      row({ photos: [PHOTO], hidePhotosFromNonConnections: false }),
    );
    expect(dto.photoUrls).toEqual(['https://signed/u1/a.jpg']);
    expect(dto.photoProtected).toBe(false);
  });

  it('withholds them from a stranger, and says why', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [PHOTO],
        hidePhotosFromNonConnections: true,
        receivedInterests: [],
        sentInterests: [],
      }),
    );
    // No signed URL is produced at all — hiding this in the client would
    // still have put a working link on the wire.
    expect(dto.photoUrls).toEqual([]);
    expect(dto.photoProtected).toBe(true);
  });

  it('serves them to someone whose interest this member accepted', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [PHOTO],
        hidePhotosFromNonConnections: true,
        receivedInterests: [{ id: 'i1' }],
        sentInterests: [],
      }),
    );
    expect(dto.photoUrls).toEqual(['https://signed/u1/a.jpg']);
    expect(dto.photoProtected).toBe(false);
  });

  it('serves them to someone who accepted this member’s interest', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [PHOTO],
        hidePhotosFromNonConnections: true,
        receivedInterests: [],
        sentInterests: [{ id: 'i2' }],
      }),
    );
    expect(dto.photoUrls).toEqual(['https://signed/u1/a.jpg']);
  });

  it('fails closed when the row was selected without the connection probes', async () => {
    // A caller that forgets `feedProfileSelectFor` hides the photos rather
    // than leaking them.
    const dto = await mapper.toDto(
      row({ photos: [PHOTO], hidePhotosFromNonConnections: true }),
    );
    expect(dto.photoUrls).toEqual([]);
    expect(dto.photoProtected).toBe(true);
  });

  it('hides the photos without hiding the member', async () => {
    // The card still renders — name, age, everything else. Only the images go.
    const dto = await mapper.toDto(
      row({ photos: [PHOTO], hidePhotosFromNonConnections: true }),
    );
    expect(dto.id).toBe('u1');
    expect(dto.name).toBe('A B');
  });
});

describe('feedProfileSelectFor', () => {
  const select = feedProfileSelectFor('viewer-1') as unknown as {
    user: { select: Record<string, unknown> };
  };

  it('asks for the privacy flag', () => {
    expect(select.user.select.hidePhotosFromNonConnections).toBe(true);
  });

  it('probes both directions of an accepted interest, for this viewer only', () => {
    expect(select.user.select.receivedInterests).toEqual({
      where: { senderId: 'viewer-1', status: 'ACCEPTED' },
      select: { id: true },
      take: 1,
    });
    expect(select.user.select.sentInterests).toEqual({
      where: { receiverId: 'viewer-1', status: 'ACCEPTED' },
      select: { id: true },
      take: 1,
    });
  });

  it('keeps the rest of the card selection intact', () => {
    // The probes ride along on the query that already runs; they must not
    // replace the columns the card is built from.
    expect(select.user.select.photos).toBeDefined();
    expect(select.user.select.partnerPreference).toBeDefined();
    expect(select.user.select.faceVerification).toBeDefined();
  });
});
