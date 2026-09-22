import type { S3Service } from '@app/storage';
import type { PrismaService } from '@app/database';
import { activePremiumSubscriptionWhere } from '@app/database';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import {
  FeedRepository,
  feedProfileSelectFor,
  type FeedProfileRow,
} from '../repositories/feed.repository';
import { arePhotosHidden, isPremiumMember } from '../privacy/photo-visibility';

/**
 * "Hide my photos from people I'm not connected with" — a PREMIUM feature.
 *
 * Enforced in the mapper, which backs EVERY profile card (feed, search, near
 * me, profile views, shortlist, interests, chat, blocks), and fed by
 * `feedProfileSelectFor(viewerId)`, which asks the database — in the same
 * query — whether the member is premium and whether this particular viewer is
 * connected. A connection is an accepted interest in either direction, the
 * app's own definition of a match.
 *
 *   premium  flag  viewer      → photos
 *   no       off   anyone      → visible
 *   no       on    anyone      → visible (feature unavailable, flag ignored)
 *   yes      off   anyone      → visible
 *   yes      on    stranger    → hidden, photoUrls = [], photoProtected
 *   yes      on    connection  → visible
 */
function makeS3() {
  const getPresignedGetUrl = jest.fn((key: string) =>
    Promise.resolve(`https://signed/${key}`),
  );
  const s3 = {
    isConfigured: () => true,
    getPresignedGetUrl,
  } as unknown as S3Service;
  return { s3, getPresignedGetUrl };
}

const PHOTO = { id: 'photo-1', s3Key: 'u1/a.jpg', isPrimary: true };
const PREMIUM = [{ id: 'sub-1' }];
const NOT_PREMIUM: Array<{ id: string }> = [];
const STRANGER = { receivedInterests: [], sentInterests: [] };

function row(user: Record<string, unknown>): FeedProfileRow {
  return { userId: 'u1', firstName: 'A', lastName: 'B', user };
}

describe('photo privacy — premium x flag x connection matrix', () => {
  const { s3, getPresignedGetUrl } = makeS3();
  const mapper = new ProfileFeedMapper(s3);

  beforeEach(() => getPresignedGetUrl.mockClear());

  it('non-premium + privacy OFF: photos visible', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [PHOTO],
        hidePhotosFromNonConnections: false,
        subscriptions: NOT_PREMIUM,
        ...STRANGER,
      }),
    );
    expect(dto.photoUrls).toEqual(['https://signed/u1/a.jpg']);
    expect(dto.photoProtected).toBe(false);
  });

  it('non-premium + privacy ON: photos stay visible — premium-only privacy is unavailable', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [PHOTO],
        hidePhotosFromNonConnections: true,
        subscriptions: NOT_PREMIUM,
        ...STRANGER,
      }),
    );
    expect(dto.photoUrls).toEqual(['https://signed/u1/a.jpg']);
    expect(dto.photoProtected).toBe(false);
  });

  it('premium + privacy OFF: photos visible', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [PHOTO],
        hidePhotosFromNonConnections: false,
        subscriptions: PREMIUM,
        ...STRANGER,
      }),
    );
    expect(dto.photoUrls).toEqual(['https://signed/u1/a.jpg']);
    expect(dto.photoProtected).toBe(false);
  });

  it('premium + privacy ON + stranger: withheld, says why, and nothing is signed', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [PHOTO],
        hidePhotosFromNonConnections: true,
        subscriptions: PREMIUM,
        ...STRANGER,
      }),
    );
    // No signed URL is produced at all — hiding this in the client would
    // still have put a working link on the wire.
    expect(dto.photoUrls).toEqual([]);
    expect(dto.photoProtected).toBe(true);
    expect(getPresignedGetUrl).not.toHaveBeenCalled();
  });

  it('premium + privacy ON + connected (viewer sent, owner accepted): visible', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [PHOTO],
        hidePhotosFromNonConnections: true,
        subscriptions: PREMIUM,
        receivedInterests: [{ id: 'i1' }],
        sentInterests: [],
      }),
    );
    expect(dto.photoUrls).toEqual(['https://signed/u1/a.jpg']);
    expect(dto.photoProtected).toBe(false);
  });

  it('premium + privacy ON + connected (owner sent, viewer accepted): visible', async () => {
    const dto = await mapper.toDto(
      row({
        photos: [PHOTO],
        hidePhotosFromNonConnections: true,
        subscriptions: PREMIUM,
        receivedInterests: [],
        sentInterests: [{ id: 'i2' }],
      }),
    );
    expect(dto.photoUrls).toEqual(['https://signed/u1/a.jpg']);
    expect(dto.photoProtected).toBe(false);
  });

  it('hides the photos without hiding the member', async () => {
    // The card still renders — name, age, everything else. Only the images go.
    const dto = await mapper.toDto(
      row({
        photos: [PHOTO],
        hidePhotosFromNonConnections: true,
        subscriptions: PREMIUM,
        ...STRANGER,
      }),
    );
    expect(dto.id).toBe('u1');
    expect(dto.name).toBe('A B');
  });

  it('a page of mixed members signs only the photos each viewer may see', async () => {
    const rows = [
      row({ photos: [PHOTO], hidePhotosFromNonConnections: false }),
      {
        ...row({
          photos: [{ id: 'p2', s3Key: 'u2/a.jpg', isPrimary: true }],
          hidePhotosFromNonConnections: true,
          subscriptions: PREMIUM,
          ...STRANGER,
        }),
        userId: 'u2',
      },
    ];
    const dtos = await mapper.toDtoList(rows);
    expect(dtos.map((d) => d.photoUrls)).toEqual([
      ['https://signed/u1/a.jpg'],
      [],
    ]);
    expect(getPresignedGetUrl).toHaveBeenCalledTimes(1);
    expect(getPresignedGetUrl).not.toHaveBeenCalledWith('u2/a.jpg');
  });
});

describe('photo privacy — fails closed', () => {
  const { s3, getPresignedGetUrl } = makeS3();
  const mapper = new ProfileFeedMapper(s3);

  beforeEach(() => getPresignedGetUrl.mockClear());

  it('flag on, row selected without ANY probes: hidden', async () => {
    // A caller that forgets `feedProfileSelectFor` hides the photos rather
    // than leaking them.
    const dto = await mapper.toDto(
      row({ photos: [PHOTO], hidePhotosFromNonConnections: true }),
    );
    expect(dto.photoUrls).toEqual([]);
    expect(dto.photoProtected).toBe(true);
    expect(getPresignedGetUrl).not.toHaveBeenCalled();
  });

  it('flag on, premium probe missing: treated as premium, hidden', () => {
    expect(
      arePhotosHidden({ hidePhotosFromNonConnections: true, ...STRANGER }),
    ).toBe(true);
  });

  it('flag on, premium, connection probes missing: treated as a stranger, hidden', () => {
    expect(
      arePhotosHidden({
        hidePhotosFromNonConnections: true,
        subscriptions: PREMIUM,
      }),
    ).toBe(true);
  });

  it('flag off: missing probes never hide anything', () => {
    expect(arePhotosHidden({})).toBe(false);
    expect(arePhotosHidden({ hidePhotosFromNonConnections: false })).toBe(
      false,
    );
  });
});

describe('isPremium on the card', () => {
  const mapper = new ProfileFeedMapper(makeS3().s3);

  it('comes from the member’s own subscription probe', async () => {
    const premium = await mapper.toDto(row({ subscriptions: PREMIUM }));
    const free = await mapper.toDto(row({ subscriptions: NOT_PREMIUM }));
    expect(premium.isPremium).toBe(true);
    expect(free.isPremium).toBe(false);
  });

  it('is false when the probe was not selected (display only, not a security gate)', () => {
    expect(isPremiumMember({})).toBe(false);
  });
});

describe('feedProfileSelectFor', () => {
  const NOW = new Date('2026-09-22T00:00:00.000Z');
  const select = feedProfileSelectFor('viewer-1', NOW) as unknown as {
    user: { select: Record<string, unknown> };
  };

  it('asks for the privacy flag', () => {
    expect(select.user.select.hidePhotosFromNonConnections).toBe(true);
  });

  it('probes both directions of an ACCEPTED interest, for this viewer only', () => {
    // Pending and declined interests are not connections: the probes filter
    // on ACCEPTED, so such rows never come back.
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

  it('probes the member’s own active premium subscription with the shared rule', () => {
    expect(select.user.select.subscriptions).toEqual({
      where: activePremiumSubscriptionWhere(NOW),
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

describe('no N+1', () => {
  it('a page of cards is ONE row query, carrying every per-candidate probe', async () => {
    type FindManyArgs = {
      select: { user: { select: Record<string, unknown> } };
    };
    const findMany = jest
      .fn<Promise<unknown[]>, [FindManyArgs]>()
      .mockResolvedValue([]);
    const count = jest.fn().mockResolvedValue(0);
    const repository = new FeedRepository({
      userProfile: { findMany, count },
    } as unknown as PrismaService);

    await repository.findMatching({}, { skip: 0, take: 20 }, 'viewer-1');

    expect(findMany).toHaveBeenCalledTimes(1);
    const [args] = findMany.mock.calls[0];
    expect(Object.keys(args.select.user.select)).toEqual(
      expect.arrayContaining([
        'subscriptions',
        'receivedInterests',
        'sentInterests',
      ]),
    );
  });
});
