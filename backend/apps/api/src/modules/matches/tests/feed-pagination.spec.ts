import type { S3Service } from '@app/storage';
import { FeedService } from '../services/feed.service';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import { CompatibilityService } from '../scoring/compatibility.service';
import { RankingService } from '../scoring/ranking.service';
import type { FeedSeenService } from '../cache/feed-seen.cache';
import type { FeedVersionService } from '../cache/feed-version.cache';
import type { RecommendationService } from '../recommendation/recommendation.service';
import type { FeedProfileRow } from '../repositories/feed.repository';

/**
 * `hasMore` without a COUNT.
 *
 * Discover used to answer "is there another page?" by counting every matching
 * profile in the database — the most expensive query in the feed, for a number
 * no client reads. The pool is now fetched one row wider than the page needs,
 * and the answer falls out of the rows themselves.
 */
const s3 = {
  isConfigured: () => false,
  getPresignedGetUrl: () => Promise.resolve(''),
} as unknown as S3Service;

function row(i: number): FeedProfileRow {
  return {
    userId: `u${String(i).padStart(4, '0')}`,
    firstName: 'A',
    lastName: 'B',
    dob: new Date('1996-01-01'),
    gender: 'FEMALE',
    createdAt: new Date(Date.UTC(2026, 0, 1) - i * 1000),
    user: {},
  };
}

type FeedQuery = { skip: number; take: number };

function build(poolRows: FeedProfileRow[]) {
  const getFeedForUser = jest
    .fn<Promise<unknown>, [string, FeedQuery]>()
    .mockResolvedValue({
      rows: poolRows,
      // No `total`: the strategy no longer counts, and this asserts FeedService
      // never reaches for one.
      tier: 1,
      fallbackUsed: false,
      reason: '',
      relaxedFilters: [],
      seeker: null,
      seekerPreference: null,
    });

  const service = new FeedService(
    { getFeedForUser } as unknown as RecommendationService,
    new ProfileFeedMapper(s3),
    new CompatibilityService(),
    new RankingService(),
    {
      get: jest.fn().mockResolvedValue(new Set<string>()),
      record: jest.fn().mockResolvedValue(undefined),
    } as unknown as FeedSeenService,
    {
      get: jest.fn().mockResolvedValue(3),
    } as unknown as FeedVersionService,
  );

  return { service, getFeedForUser };
}

describe('Discover pagination without a COUNT', () => {
  it('asks for one row more than the page needs', async () => {
    const { service, getFeedForUser } = build([]);

    await service.getFeed('me', { page: 1, limit: 20 });

    // The pool is deliberately wider than one page (ranking needs candidates
    // to choose from); the `+ 1` on top is what makes hasMore answerable.
    const [, query] = getFeedForUser.mock.calls[0];
    expect(query.skip).toBe(0);
    expect(query.take).toBe(201);
  });

  it('exactly `limit` candidates: hasMore is false', async () => {
    const { service } = build(Array.from({ length: 20 }, (_, i) => row(i)));

    const result = await service.getFeed('me', { page: 1, limit: 20 });

    expect(result.items).toHaveLength(20);
    expect(result.hasMore).toBe(false);
  });

  it('`limit + 1` candidates: hasMore is true and only `limit` items are returned', async () => {
    const { service } = build(Array.from({ length: 21 }, (_, i) => row(i)));

    const result = await service.getFeed('me', { page: 1, limit: 20 });

    expect(result.items).toHaveLength(20);
    expect(result.hasMore).toBe(true);
  });

  it('never returns more items than the requested limit', async () => {
    const { service } = build(Array.from({ length: 200 }, (_, i) => row(i)));

    for (const limit of [1, 5, 20, 50]) {
      const result = await service.getFeed('me', { page: 1, limit });
      expect(result.items.length).toBeLessThanOrEqual(limit);
    }
  });

  it('an empty feed reports hasMore false', async () => {
    const { service } = build([]);

    const result = await service.getFeed('me', { page: 1, limit: 20 });

    expect(result.items).toEqual([]);
    expect(result.hasMore).toBe(false);
  });

  it('the last page reports hasMore false, the one before it true', async () => {
    // 45 candidates, 20 per page: pages 1 and 2 have more after them, page 3
    // (the final 5) does not.
    const { service } = build(Array.from({ length: 45 }, (_, i) => row(i)));

    const first = await service.getFeed('me', { page: 1, limit: 20 });
    const second = await service.getFeed('me', { page: 2, limit: 20 });
    const third = await service.getFeed('me', { page: 3, limit: 20 });

    expect([first.hasMore, second.hasMore, third.hasMore]).toEqual([
      true,
      true,
      false,
    ]);
    expect(third.items).toHaveLength(5);
  });

  it('no page repeats a profile from the page before it', async () => {
    const { service } = build(Array.from({ length: 45 }, (_, i) => row(i)));

    const pages = await Promise.all([
      service.getFeed('me', { page: 1, limit: 20 }),
      service.getFeed('me', { page: 2, limit: 20 }),
      service.getFeed('me', { page: 3, limit: 20 }),
    ]);

    const ids = pages.flatMap((p) => p.items.map((i) => i.id));
    expect(ids).toHaveLength(45);
    expect(new Set(ids).size).toBe(45);
  });

  it('cursor paging still ends by cursor, not by a count', async () => {
    const { service } = build(Array.from({ length: 30 }, (_, i) => row(i)));

    const first = await service.getFeed('me', { limit: 20 });
    expect(first.nextCursor).not.toBeNull();
    expect(first.hasMore).toBe(true);

    const second = await service.getFeed('me', {
      limit: 20,
      cursor: first.nextCursor ?? undefined,
    });
    // 10 left after the first page — short of a full page, so this is the end.
    expect(second.items).toHaveLength(10);
    expect(second.nextCursor).toBeNull();
    expect(second.hasMore).toBe(false);

    const firstIds = first.items.map((i) => i.id);
    const secondIds = second.items.map((i) => i.id);
    expect(firstIds.filter((id) => secondIds.includes(id))).toEqual([]);
  });

  it('omits total from the Discover response entirely', async () => {
    const { service } = build(Array.from({ length: 30 }, (_, i) => row(i)));

    const result = await service.getFeed('me', { page: 1, limit: 20 });

    // Not zero, not a guess — absent. Search keeps its own real total.
    expect(result.total).toBeUndefined();
    expect(Object.keys(result)).not.toContain('total');
  });
});
