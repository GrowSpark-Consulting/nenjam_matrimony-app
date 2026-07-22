import { ProgressiveFallbackStrategy } from './progressive-fallback.strategy';
import type { FeedRepository, FeedProfileRow } from '../repositories/feed.repository';
import type { PreferenceRepository } from '../repositories/preference.repository';
import type { AppConfigService } from '@app/config';

const SELF = {
  gender: 'MALE' as const,
  caste: 'Iyer',
  currentCity: 'Chennai',
  currentState: 'Tamil Nadu',
  motherTongue: 'Tamil',
};

const FULL_PREF = {
  minAge: 25,
  maxAge: 30,
  minHeightCm: 150,
  maxHeightCm: 175,
  preferredReligions: ['Hindu'],
  preferredCastes: ['Same Caste'],
  preferredMotherTongues: ['Same Mother Tongue'],
  preferredEducation: [],
  preferredOccupations: [],
  preferredCities: [],
  preferredStates: [],
  maritalStatusPref: [],
  minIncomeLakhs: null,
} as never;

function makeRow(id: string): FeedProfileRow {
  return { userId: id } as FeedProfileRow;
}

function buildStrategy(opts: {
  self?: typeof SELF | null;
  pref?: unknown;
  countSequence: number[];
  rows?: FeedProfileRow[];
  config?: Partial<{ enabled: boolean; ageRelaxStep1: number; ageRelaxStep2: number; maxTier: number }>;
}) {
  const countMatching = jest.fn();
  opts.countSequence.forEach((c) => countMatching.mockResolvedValueOnce(c));

  const findRows = jest.fn().mockResolvedValue(opts.rows ?? []);

  const feedRepository = {
    findSelf: jest.fn().mockResolvedValue(opts.self ?? SELF),
    countMatching,
    findRows,
    findMatching: jest.fn(),
  } as unknown as FeedRepository;

  const preferenceRepository = {
    findByUserId: jest.fn().mockResolvedValue(opts.pref ?? FULL_PREF),
    upsert: jest.fn(),
  } as unknown as PreferenceRepository;

  const configService = {
    fallback: {
      enabled: true,
      ageRelaxStep1: 2,
      ageRelaxStep2: 5,
      maxTier: 10,
      ...opts.config,
    },
  } as unknown as AppConfigService;

  const strategy = new ProgressiveFallbackStrategy(
    feedRepository,
    preferenceRepository,
    configService,
  );

  return { strategy, countMatching, findRows };
}

describe('ProgressiveFallbackStrategy', () => {
  it('exact match exists: Tier 1 returns immediately, fallbackUsed=false, no further tiers tried', async () => {
    const { strategy, countMatching, findRows } = buildStrategy({
      countSequence: [4], // Tier 1 alone has candidates
      rows: [makeRow('a'), makeRow('b')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(1);
    expect(result.fallbackUsed).toBe(false);
    expect(result.total).toBe(4);
    expect(result.rows).toHaveLength(2);
    expect(countMatching).toHaveBeenCalledTimes(1); // stopped at tier 1, never tried tier 2+
    expect(findRows).toHaveBeenCalledTimes(1);
  });

  it('exact match missing, Tier 2 returns users: stops at tier 2, fallbackUsed=true', async () => {
    const { strategy, countMatching, findRows } = buildStrategy({
      countSequence: [0, 3], // tier1 empty, tier2 has 3
      rows: [makeRow('a'), makeRow('b'), makeRow('c')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(2);
    expect(result.fallbackUsed).toBe(true);
    expect(result.relaxedFilters).toEqual(['Age']);
    expect(countMatching).toHaveBeenCalledTimes(2);
    expect(findRows).toHaveBeenCalledTimes(1); // only the winning tier fetches rows
  });

  it('Tier 3 returns users: tiers 1-2 tried and logged as empty first', async () => {
    const { strategy, countMatching } = buildStrategy({
      countSequence: [0, 0, 6], // tier1, tier2 empty, tier3 has 6
      rows: [makeRow('a')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(3);
    expect(result.relaxedFilters).toEqual(['Age', 'City']);
    expect(countMatching).toHaveBeenCalledTimes(3);
  });

  it('Tier 10 returns users: every relaxation exhausted before the gender-only tier succeeds', async () => {
    const { strategy, countMatching, findRows } = buildStrategy({
      countSequence: [0, 0, 0, 0, 0, 0, 0, 0, 0, 7], // tiers 1-9 empty, tier10 has 7
      rows: [makeRow('a')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(10);
    expect(result.fallbackUsed).toBe(true);
    expect(countMatching).toHaveBeenCalledTimes(10);
    expect(findRows).toHaveBeenCalledTimes(1);
    // Tier 10's WHERE must still be a safety-exclusion-wrapped, gender-only query.
    const tier10Where = countMatching.mock.calls[9][0];
    expect(JSON.stringify(tier10Where)).toContain('ACTIVE');
  });

  it('no users in database (every tier empty, including Tier 10): returns an honest empty feed, not an error', async () => {
    const { strategy } = buildStrategy({
      countSequence: new Array(10).fill(0),
      rows: [],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(10);
    expect(result.total).toBe(0);
    expect(result.rows).toEqual([]);
  });

  it('pagination: skip/take are forwarded unchanged to the winning tier\'s row fetch', async () => {
    const { strategy, findRows } = buildStrategy({
      countSequence: [5],
      rows: [makeRow('a')],
    });

    await strategy.getFeedForUser('me', { skip: 40, take: 10 });

    expect(findRows).toHaveBeenCalledWith(expect.anything(), { skip: 40, take: 10 });
  });

  it('duplicate prevention: findRows is called at most once per request, never once per tier', async () => {
    const { strategy, findRows } = buildStrategy({
      countSequence: [0, 0, 0, 8],
      rows: [makeRow('a'), makeRow('b')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(findRows).toHaveBeenCalledTimes(1);
    // No duplicate ids possible from merging tiers — only one tier's rows are ever returned.
    const ids = result.rows.map((r) => (r as { userId: string }).userId);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('caller has no saved preference at all: only Tier 1 (gender-only) is tried, no fallback', async () => {
    const { strategy, countMatching } = buildStrategy({
      pref: null,
      countSequence: [9],
      rows: [makeRow('a')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(1);
    expect(result.fallbackUsed).toBe(false);
    expect(countMatching).toHaveBeenCalledTimes(1);
  });

  it('FALLBACK_ENABLED=false: stops after Tier 1 even if it is empty', async () => {
    const { strategy, countMatching } = buildStrategy({
      countSequence: [0],
      rows: [],
      config: { enabled: false },
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(1);
    expect(countMatching).toHaveBeenCalledTimes(1);
  });

  it('MAX_FALLBACK_TIER caps relaxation before Tier 10', async () => {
    const { strategy, countMatching } = buildStrategy({
      countSequence: [0, 0, 0],
      rows: [],
      config: { maxTier: 3 },
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(countMatching).toHaveBeenCalledTimes(3);
    expect(result.tier).toBe(3); // last tier tried, per the configured ceiling
  });
});
