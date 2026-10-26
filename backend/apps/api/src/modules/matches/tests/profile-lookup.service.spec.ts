import { NotFoundException } from '@nestjs/common';
import { buildEligibilityConditions } from '../filters/eligibility.builder';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
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
  const findDetailExtras = jest.fn().mockResolvedValue(extrasRow);
  // The real mapper method — it is pure, and this is the code under test for
  // "what the member saved is what is returned".
  const mapper = new ProfileFeedMapper({} as never);
  const toDetailExtras = jest.fn((row: unknown) =>
    mapper.toDetailExtras(row as never),
  );
  const service = new ProfileLookupService(
    { findSelf, findMatching, findDetailExtras } as unknown as FeedRepository,
    { toDto, toDetailExtras } as unknown as ProfileFeedMapper,
  );
  return { service, findMatching, findSelf, toDto, findDetailExtras };
}

const extrasRow = {
  fatherName: 'Ravi Kumar',
  fatherOccupation: 'Farmer',
  motherName: '',
  motherOccupation: null,
  familyType: 'Nuclear',
  familyValues: null,
  familyStatus: null,
  siblingDetails: [
    { relation: 'BROTHER', name: 'not exposed' },
    { relation: 'SISTER' },
    { relation: 'SISTER' },
  ],
  fitness: null,
  user: {
    astrologyProfile: {
      rasi: 'Kumbha',
      nakshatra: 'Sathayam',
      dosham: 'CHEVVAI',
      horoscopeAvailable: true,
    },
    partnerPreference: null,
  },
};

describe('ProfileLookupService', () => {
  it('returns a visible profile, mapped exactly as the feed maps it', async () => {
    const { service, toDto } = build([{ userId: OTHER }]);
    await expect(
      service.getVisibleProfile(VIEWER, OTHER),
    ).resolves.toMatchObject({ id: OTHER });
    expect(toDto).toHaveBeenCalledTimes(1);
  });

  it('adds the saved detail fields as-is, leaving unfilled ones empty', async () => {
    const { service, findDetailExtras } = build([{ userId: OTHER }]);
    const result = await service.getVisibleProfile(VIEWER, OTHER);

    expect(findDetailExtras).toHaveBeenCalledWith(OTHER);
    expect(result.detail.family).toEqual({
      fatherName: 'Ravi Kumar',
      fatherOccupation: 'Farmer',
      motherName: '',
      motherOccupation: '',
      familyType: 'Nuclear',
      familyValues: '',
      familyStatus: '',
      brothers: 1,
      sisters: 2,
    });
    expect(result.detail.fitness).toBe('');
    expect(result.detail.horoscope).toEqual({
      rasi: 'Kumbha',
      nakshatra: 'Sathayam',
      dosham: 'Chevvai',
      horoscopeAvailable: true,
    });
    // Never saved a preference -> null, not an invented one.
    expect(result.detail.partnerPreference).toBeNull();
    // Sibling names are stored but never exposed.
    expect(JSON.stringify(result)).not.toContain('not exposed');
  });

  it('maps a member with no astrology row or preference to empty values', async () => {
    const { service, findDetailExtras } = build([{ userId: OTHER }]);
    findDetailExtras.mockResolvedValueOnce({
      ...extrasRow,
      siblingDetails: [],
      user: { astrologyProfile: null, partnerPreference: null },
    });
    const { detail } = await service.getVisibleProfile(VIEWER, OTHER);
    expect(detail.horoscope).toEqual({
      rasi: '',
      nakshatra: '',
      dosham: '',
      horoscopeAvailable: false,
    });
    expect(detail.family.brothers).toBe(0);
    expect(detail.family.sisters).toBe(0);
  });

  it('maps a saved partner preference without inventing bounds', async () => {
    const { service, findDetailExtras } = build([{ userId: OTHER }]);
    findDetailExtras.mockResolvedValueOnce({
      ...extrasRow,
      user: {
        astrologyProfile: null,
        partnerPreference: {
          minAge: 25,
          maxAge: null,
          minHeightCm: null,
          maxHeightCm: null,
          preferredReligions: ['Hindu'],
          preferredCastes: [],
          preferredEducation: [],
          preferredOccupations: [],
          minIncomeLakhs: '12.50',
          preferredCities: [],
          preferredStates: ['Tamil Nadu'],
          preferredMotherTongues: [],
          maritalStatusPref: ['NEVER_MARRIED'],
        },
      },
    });
    const { detail } = await service.getVisibleProfile(VIEWER, OTHER);
    expect(detail.partnerPreference).toMatchObject({
      minAge: 25,
      maxAge: null,
      religions: ['Hindu'],
      minIncomeLakhs: 12.5,
      states: ['Tamil Nadu'],
      maritalStatuses: ['Never Married'],
    });
  });

  it('never reads detail fields for a profile the viewer cannot see', async () => {
    const { service, findDetailExtras } = build([]);
    await expect(
      service.getVisibleProfile(VIEWER, OTHER),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(findDetailExtras).not.toHaveBeenCalled();
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
