import { BadRequestException } from '@nestjs/common';
import { NearbyService } from './nearby.service';
import type {
  NearbyCandidate,
  NearbyRepository,
  NearbySelf,
} from '../repositories/nearby.repository';
import type { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import type { FeedProfileRow } from '../repositories/feed.repository';
import type { DiscoverProfileDto } from '../dto/discover-profile.response.dto';

const SELF: NearbySelf = {
  gender: 'MALE',
  latitude: 13.0827,
  longitude: 80.2707,
};

const CHENNAI = { latitude: 13.0827, longitude: 80.2707 };

function makeRow(userId: string): FeedProfileRow {
  return { userId };
}

/**
 * Stand-in mapper: echoes the row id and leaves distanceKm null, exactly as
 * the real ProfileFeedMapper does. The service is what fills the distance in,
 * so a double that pre-filled it would hide the bug this suite exists to
 * catch.
 */
function makeMapper(): ProfileFeedMapper {
  return {
    toDtoList: jest.fn((rows: FeedProfileRow[]) =>
      Promise.resolve(
        rows.map(
          (row) =>
            ({
              id: String(row.userId),
              name: `User ${String(row.userId)}`,
              distanceKm: null,
            }) as unknown as DiscoverProfileDto,
        ),
      ),
    ),
  } as unknown as ProfileFeedMapper;
}

function buildService(opts: {
  self?: NearbySelf | null;
  candidates?: NearbyCandidate[];
  visibleRows?: FeedProfileRow[];
}) {
  const candidates = opts.candidates ?? [];

  // Held as standalone consts rather than reached through `repository.x` at
  // the assertion site: passing a method reference off its object is exactly
  // what the unbound-method rule flags, and these are plain mocks anyway.
  const findSelf = jest.fn(() =>
    Promise.resolve(opts.self === undefined ? SELF : opts.self),
  );
  const findCandidatesWithin = jest.fn(() => Promise.resolve(candidates));
  const findVisibleProfiles = jest.fn(() =>
    Promise.resolve(
      opts.visibleRows ?? candidates.map((c) => makeRow(c.userId)),
    ),
  );

  const repository = {
    findSelf,
    findCandidatesWithin,
    findVisibleProfiles,
  } as unknown as NearbyRepository;

  return {
    service: new NearbyService(repository, makeMapper()),
    findCandidatesWithin,
    findVisibleProfiles,
  };
}

describe('NearbyService', () => {
  it('sorts results by ascending distance', async () => {
    const { service } = buildService({
      candidates: [
        { userId: 'c', distanceKm: 45.0 },
        { userId: 'a', distanceKm: 2.34 },
        { userId: 'b', distanceKm: 8.72 },
      ],
      // Deliberately a different order: Postgres gives no ordering guarantee
      // for an IN (...) match, so the service must re-sort rather than trust
      // the order rows came back in.
      visibleRows: [makeRow('b'), makeRow('c'), makeRow('a')],
    });

    const result = await service.findNearby('me', { ...CHENNAI });

    expect(result.profiles.map((p) => p.id)).toEqual(['a', 'b', 'c']);
    expect(result.profiles.map((p) => p.distanceKm)).toEqual([2.3, 8.7, 45]);
  });

  it('fills distanceKm on every profile the mapper left null', async () => {
    const { service } = buildService({
      candidates: [{ userId: 'a', distanceKm: 12.345 }],
    });

    const result = await service.findNearby('me', { ...CHENNAI });

    expect(result.profiles[0].distanceKm).toBe(12.3);
  });

  it('never exposes the coordinates of another member', async () => {
    const { service } = buildService({
      candidates: [{ userId: 'a', distanceKm: 5 }],
    });

    const result = await service.findNearby('me', { ...CHENNAI });

    expect(result.profiles[0]).not.toHaveProperty('latitude');
    expect(result.profiles[0]).not.toHaveProperty('longitude');
  });

  it('drops candidates the safety filters removed', async () => {
    // Geographically nearby, but blocked / declined / suspended, so the second
    // phase does not return the row. It must not appear and must not count
    // toward the total.
    const { service } = buildService({
      candidates: [
        { userId: 'a', distanceKm: 1 },
        { userId: 'b', distanceKm: 2 },
        { userId: 'c', distanceKm: 3 },
      ],
      visibleRows: [makeRow('a'), makeRow('c')],
    });

    const result = await service.findNearby('me', { ...CHENNAI });

    expect(result.profiles.map((p) => p.id)).toEqual(['a', 'c']);
    expect(result.total).toBe(2);
  });

  it('paginates over the distance-sorted list', async () => {
    const candidates = Array.from({ length: 5 }, (_, i) => ({
      userId: `u${i}`,
      distanceKm: i + 1,
    }));

    const { service } = buildService({ candidates });

    const page2 = await service.findNearby('me', {
      ...CHENNAI,
      page: 2,
      limit: 2,
    });

    expect(page2.profiles.map((p) => p.id)).toEqual(['u2', 'u3']);
    expect(page2.total).toBe(5);
    expect(page2.hasMore).toBe(true);

    const page3 = await service.findNearby('me', {
      ...CHENNAI,
      page: 3,
      limit: 2,
    });
    expect(page3.profiles.map((p) => p.id)).toEqual(['u4']);
    expect(page3.hasMore).toBe(false);
  });

  it('breaks distance ties deterministically', async () => {
    // Two profiles at an identical distance must keep a stable order between
    // requests, or one can appear on both page 1 and page 2 while the other is
    // skipped entirely.
    const { service } = buildService({
      candidates: [
        { userId: 'zeta', distanceKm: 4 },
        { userId: 'alpha', distanceKm: 4 },
      ],
      visibleRows: [makeRow('zeta'), makeRow('alpha')],
    });

    const first = await service.findNearby('me', { ...CHENNAI });
    const second = await service.findNearby('me', { ...CHENNAI });

    expect(first.profiles.map((p) => p.id)).toEqual(['alpha', 'zeta']);
    expect(second.profiles.map((p) => p.id)).toEqual(
      first.profiles.map((p) => p.id),
    );
  });

  it('searches for the opposite gender', async () => {
    const { service, findCandidatesWithin } = buildService({
      candidates: [],
    });

    await service.findNearby('me', { ...CHENNAI });

    expect(findCandidatesWithin).toHaveBeenCalledWith(
      CHENNAI,
      100,
      'FEMALE',
      'me',
    );
  });

  it('falls back to the stored location when the query omits coordinates', async () => {
    const { service, findCandidatesWithin } = buildService({
      candidates: [],
    });

    await service.findNearby('me', {});

    expect(findCandidatesWithin).toHaveBeenCalledWith(
      { latitude: SELF.latitude, longitude: SELF.longitude },
      100,
      expect.anything(),
      'me',
    );
  });

  it('never searches beyond the 100km ceiling', async () => {
    // The DTO validator rejects an over-large radius at the HTTP boundary, so
    // this covers the service's own clamp — the guard that still holds if this
    // service is ever called from somewhere that is not that controller.
    const { service, findCandidatesWithin } = buildService({ candidates: [] });

    const result = await service.findNearby('me', {
      ...CHENNAI,
      radiusKm: 500,
    });

    expect(findCandidatesWithin).toHaveBeenCalledWith(
      CHENNAI,
      100,
      expect.anything(),
      'me',
    );
    expect(result.radiusKm).toBe(100);
  });

  it('rejects half a coordinate pair', async () => {
    const { service } = buildService({ candidates: [] });

    await expect(
      service.findNearby('me', { latitude: 13.0827 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a request with no coordinates anywhere', async () => {
    const { service } = buildService({
      self: { gender: 'MALE', latitude: null, longitude: null },
      candidates: [],
    });

    await expect(service.findNearby('me', {})).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('returns an empty page when the caller has no finalized profile', async () => {
    // Their gender is unknown, so the mandatory opposite-gender rule cannot be
    // resolved. Fails closed with zero results rather than returning a
    // mixed-gender list.
    const { service, findCandidatesWithin } = buildService({ self: null });

    const result = await service.findNearby('me', { ...CHENNAI });

    expect(result).toMatchObject({ success: true, profiles: [], total: 0 });
    expect(findCandidatesWithin).not.toHaveBeenCalled();
  });

  it('returns an empty page when nobody is in range, without a second query', async () => {
    const { service, findVisibleProfiles } = buildService({
      candidates: [],
    });

    const result = await service.findNearby('me', { ...CHENNAI });

    expect(result.profiles).toEqual([]);
    expect(result.hasMore).toBe(false);
    expect(findVisibleProfiles).not.toHaveBeenCalled();
  });

  it('echoes the applied radius so the client can label the empty state', async () => {
    const { service } = buildService({ candidates: [] });

    const result = await service.findNearby('me', { ...CHENNAI, radiusKm: 25 });

    expect(result.radiusKm).toBe(25);
  });
});
