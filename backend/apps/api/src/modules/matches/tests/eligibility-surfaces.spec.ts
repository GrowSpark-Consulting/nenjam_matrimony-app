import type { PrismaService } from '@app/database';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { buildEligibilityConditions } from '../filters/eligibility.builder';
import { PostgresSearchStrategy } from '../search/postgres-search.strategy';
import { NearbyRepository } from '../repositories/nearby.repository';
import type { FeedRepository } from '../repositories/feed.repository';
import type { PreferenceRepository } from '../repositories/preference.repository';
import { freezeClock } from './freeze-clock';

type Where = Prisma.UserProfileWhereInput;

// Eligibility embeds the current time (subscription expiry); pin it so the
// rules built here equal the ones each surface builds internally.
freezeClock();

/**
 * The query each non-Discover surface actually sends carries the complete
 * shared eligibility — including the declined-interest rule (F5) that Search
 * used to lack. Discover's tiers are covered in
 * progressive-fallback.strategy.spec.ts.
 */
const ME = 'me';
const eligibility = buildEligibilityConditions({
  currentUserId: ME,
  myGender: 'MALE',
});

function expectEveryRule(where: Where): void {
  const and = where.AND as Where[];
  for (const rule of eligibility) {
    expect(and).toContainEqual(rule);
  }
  expect(JSON.stringify(where)).toContain('"status":"DECLINED"');
  // A hidden premium profile can't be reached through an alternate
  // discovery surface either.
  expect(JSON.stringify(where)).toContain('"profileVisibleToPremiumOnly":true');
}

describe('Search uses the shared eligibility', () => {
  function build() {
    const findMatching = jest.fn().mockResolvedValue({ rows: [], total: 0 });
    const strategy = new PostgresSearchStrategy(
      {
        findSelf: jest.fn().mockResolvedValue({ gender: 'MALE', caste: null }),
        findMatching,
      } as unknown as FeedRepository,
      {
        findByUserId: jest
          .fn()
          .mockResolvedValue({ preferredReligions: ['Hindu'] }),
      } as unknown as PreferenceRepository,
    );
    return { strategy, findMatching };
  }

  it('with a search term', async () => {
    const { strategy, findMatching } = build();
    await strategy.search(ME, 'engineer', { skip: 0, take: 20 });
    expectEveryRule(findMatching.mock.calls[0][0] as Where);
  });

  it('with an empty search term', async () => {
    const { strategy, findMatching } = build();
    await strategy.search(ME, '', { skip: 0, take: 20 });
    expectEveryRule(findMatching.mock.calls[0][0] as Where);
  });
});

describe('Near Me uses the shared eligibility', () => {
  it('re-fetches geographic hits through every eligibility rule', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const repository = new NearbyRepository({
      userProfile: { findMany },
    } as unknown as PrismaService);

    await repository.findVisibleProfiles(['a', 'b'], ME, 'MALE');

    const where = (findMany.mock.calls[0][0] as { where: Where }).where;
    expect(where.AND as Where[]).toContainEqual({ userId: { in: ['a', 'b'] } });
    expectEveryRule(where);
  });

  it('asks the database nothing for an empty hit list', async () => {
    const findMany = jest.fn();
    const repository = new NearbyRepository({
      userProfile: { findMany },
    } as unknown as PrismaService);

    await expect(
      repository.findVisibleProfiles([], ME, 'MALE'),
    ).resolves.toEqual([]);
    expect(findMany).not.toHaveBeenCalled();
  });
});
