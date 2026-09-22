import { ProgressiveFallbackStrategy } from './progressive-fallback.strategy';
import type {
  FeedRepository,
  FeedProfileRow,
} from '../repositories/feed.repository';
import type { PreferenceRepository } from '../repositories/preference.repository';
import type { AppConfigService } from '@app/config';
import type { FeedContextService } from '../cache/feed-context.cache';
import { buildEligibilityConditions } from '../filters/eligibility.builder';
import { freezeClock } from '../tests/freeze-clock';

// Eligibility embeds the current time (subscription expiry); pin it so the
// rules built in a test equal the ones each tier builds internally.
freezeClock();

const SELF = {
  // The seeker's own id: the row fetch passes it through so photo privacy is
  // resolved against THIS viewer's connections.
  userId: 'me',
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
  config?: Partial<{
    enabled: boolean;
    ageRelaxStep1: number;
    ageRelaxStep2: number;
    maxTier: number;
  }>;
}) {
  const countMatching = jest.fn();
  opts.countSequence.forEach((c) => countMatching.mockResolvedValueOnce(c));

  const findRows = jest.fn().mockResolvedValue(opts.rows ?? []);

  const feedRepository = {
    // Respect an explicit `self: null` (no finalized profile); only default to
    // SELF when the caller didn't specify one at all.
    findSelf: jest.fn().mockResolvedValue('self' in opts ? opts.self : SELF),
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

  // Delegates to the same repository mocks the strategy used to call directly,
  // so every existing expectation in this file still describes the same
  // behaviour — the cache is an optimisation in front of these reads, not a
  // change to what they return.
  const feedContext = {
    load: jest.fn(async (userId: string) => ({
      self: await feedRepository.findSelf(userId),
      pref: await preferenceRepository.findByUserId(userId),
    })),
    invalidate: jest.fn(),
  } as unknown as FeedContextService;

  const strategy = new ProgressiveFallbackStrategy(
    feedRepository,
    preferenceRepository,
    configService,
    feedContext,
  );

  return { strategy, countMatching, findRows };
}

describe('ProgressiveFallbackStrategy', () => {
  it('caller has no finalized profile: short-circuits to an empty feed with INCOMPLETE_SELF_PROFILE, running zero tier probes', async () => {
    const { strategy, countMatching, findRows } = buildStrategy({
      self: null,
      countSequence: [],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.total).toBe(0);
    expect(result.rows).toEqual([]);
    expect(result.reason).toBe('INCOMPLETE_SELF_PROFILE');
    expect(result.fallbackUsed).toBe(false);
    // No pointless count/row queries — the opposite-gender rule can't be met.
    expect(countMatching).not.toHaveBeenCalled();
    expect(findRows).not.toHaveBeenCalled();
  });

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

  it('Tier 1 empty, Tier 2 has candidates: returns Tier 2 (lowest non-empty), fallbackUsed=true', async () => {
    const { strategy, countMatching, findRows } = buildStrategy({
      countSequence: [0, 3, 4, 5, 6, 7, 8, 9, 10, 11], // tier1 empty; tier2 lowest non-empty
      rows: [makeRow('a'), makeRow('b'), makeRow('c')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(2);
    expect(result.fallbackUsed).toBe(true);
    expect(result.relaxedFilters).toEqual(['Age']);
    expect(result.total).toBe(3);
    // On a Tier 1 miss, every wider tier is probed in ONE parallel batch (the
    // plan is monotonically relaxing, so the lowest-numbered non-empty tier is
    // the winner) — 1 (Tier 1) + 9 (wider) count probes, regardless of winner.
    expect(countMatching).toHaveBeenCalledTimes(10);
    expect(findRows).toHaveBeenCalledTimes(1); // only the winning tier fetches rows
  });

  it('Tier 1-2 empty, Tier 3 has candidates: returns Tier 3', async () => {
    const { strategy, countMatching } = buildStrategy({
      countSequence: [0, 0, 6, 7, 8, 9, 10, 11, 12, 13], // tier1-2 empty, tier3 lowest non-empty
      rows: [makeRow('a')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(3);
    expect(result.relaxedFilters).toEqual(['Age', 'City']);
    expect(result.total).toBe(6);
    expect(countMatching).toHaveBeenCalledTimes(10);
  });

  it('multiple wider tiers non-empty: the LOWEST-numbered one wins (guards the parallel-probe pick)', async () => {
    const { strategy, findRows } = buildStrategy({
      // Tiers 2-3 empty; tiers 4+ all have candidates. Tier 4 must win — not
      // whichever count promise happens to resolve first.
      countSequence: [0, 0, 0, 7, 8, 9, 10, 11, 12, 20],
      rows: [makeRow('a')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(4);
    expect(result.total).toBe(7);
    expect(result.relaxedFilters).toEqual(['Age', 'City', 'Caste']);
    expect(findRows).toHaveBeenCalledTimes(1);
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
    // Tier 10's WHERE must still carry the shared eligibility, gender-only
    // query — status is a denylist (not an ACTIVE allowlist): PENDING_VERIFICATION
    // must remain visible even at the loosest tier (see eligibility.builder.ts).
    const tier10Where = countMatching.mock.calls[9][0];
    expect(JSON.stringify(tier10Where)).toContain(
      '"notIn":["SUSPENDED","DEACTIVATED","BANNED"]',
    );
  });

  it('every tier, Tier 1 included, carries the full shared eligibility', async () => {
    const { strategy, countMatching } = buildStrategy({
      countSequence: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    });

    await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    const eligibility = buildEligibilityConditions({
      currentUserId: 'me',
      myGender: SELF.gender,
    });
    expect(countMatching).toHaveBeenCalledTimes(10);
    countMatching.mock.calls.forEach(([where], index) => {
      const and = (where as { AND: unknown[] }).AND;
      for (const rule of eligibility) {
        expect({
          tier: index + 1,
          has: and.some((c) => JSON.stringify(c) === JSON.stringify(rule)),
        }).toEqual({ tier: index + 1, has: true });
      }
      // F5: a declined interest is excluded at Tier 1 exactly as at Tier 10.
      expect(JSON.stringify(where)).toContain('"status":"DECLINED"');
    });
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

  it("pagination: skip/take are forwarded unchanged to the winning tier's row fetch", async () => {
    const { strategy, findRows } = buildStrategy({
      countSequence: [5],
      rows: [makeRow('a')],
    });

    await strategy.getFeedForUser('me', { skip: 40, take: 10 });

    expect(findRows).toHaveBeenCalledWith(
      expect.anything(),
      { skip: 40, take: 10 },
      'me',
    );
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
