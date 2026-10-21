import { NotFoundException } from '@nestjs/common';
import { buildEligibilityConditions } from '../filters/eligibility.builder';
import type { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import type { FeedRepository } from '../repositories/feed.repository';
import { ProfileLookupService } from '../services/profile-lookup.service';
import { freezeClock } from './freeze-clock';

freezeClock();

const VIEWER = 'viewer';
const OTHER = 'other';

function build(rows: unknown[]) {
  const findMatching = jest
    .fn<Promise<{ rows: unknown[]; total: number }>, unknown[]>()
    .mockResolvedValue({ rows, total: rows.length });
  const findSelf = jest.fn().mockResolvedValue({ gender: 'MALE' });
  const toDto = jest.fn((row: { userId: string }) =>
    Promise.resolve({ id: row.userId }),
  );
  const service = new ProfileLookupService(
    { findSelf, findMatching } as unknown as FeedRepository,
    { toDto } as unknown as ProfileFeedMapper,
  );
  return { service, findMatching, findSelf, toDto };
}

describe('ProfileLookupService', () => {
  it('returns a visible profile, mapped exactly as the feed maps it', async () => {
    const { service, toDto } = build([{ userId: OTHER }]);
    await expect(service.getVisibleProfile(VIEWER, OTHER)).resolves.toEqual({
      id: OTHER,
    });
    expect(toDto).toHaveBeenCalledTimes(1);
  });

  it('applies the full shared feed eligibility plus the requested member', async () => {
    const { service, findMatching } = build([{ userId: OTHER }]);
    await service.getVisibleProfile(VIEWER, OTHER);

    const where = findMatching.mock.calls[0][0] as { AND: unknown[] };
    const eligibility = buildEligibilityConditions({
      currentUserId: VIEWER,
      myGender: 'MALE',
    });
    for (const rule of eligibility) expect(where.AND).toContainEqual(rule);
    expect(where.AND).toContainEqual({ userId: OTHER });
    // Blocked, declined and premium-only-hidden members are refused by the
    // same rules the feed uses, not a weaker copy of them.
    expect(JSON.stringify(where)).toContain('"status":"DECLINED"');
    // Photo privacy is evaluated for THIS viewer.
    expect(findMatching.mock.calls[0][2]).toBe(VIEWER);
  });

  it('does not apply the viewer saved partner preferences', async () => {
    const { service, findMatching } = build([{ userId: OTHER }]);
    await service.getVisibleProfile(VIEWER, OTHER);
    expect(JSON.stringify(findMatching.mock.calls[0][0])).not.toContain(
      'preferredReligions',
    );
  });

  it('answers 404 for an unavailable, deleted, blocked or ineligible profile', async () => {
    const { service } = build([]);
    await expect(
      service.getVisibleProfile(VIEWER, OTHER),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('answers 404 for the viewer own id and for an empty id, without querying', async () => {
    const { service, findMatching } = build([{ userId: VIEWER }]);
    await expect(
      service.getVisibleProfile(VIEWER, VIEWER),
    ).rejects.toBeInstanceOf(NotFoundException);
    await expect(service.getVisibleProfile(VIEWER, '')).rejects.toBeInstanceOf(
      NotFoundException,
    );
    expect(findMatching).not.toHaveBeenCalled();
  });

  it('gives the same 404 whatever the reason, so it reveals nothing', async () => {
    const message = (id: string) =>
      build([])
        .service.getVisibleProfile(VIEWER, id)
        .catch((e: NotFoundException) => e.message);
    expect(await message('no-such-user')).toBe(await message(OTHER));
    expect(await message(VIEWER)).toBe(await message(OTHER));
  });
});
