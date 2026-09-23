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
  return { userId: id };
}

type FindRowsArgs = [
  where: unknown,
  page: { skip: number; take: number },
  viewerId: string,
];
/** Typed so `mock.calls` can be read without casting at every assertion. */
type FindRowsMock = jest.Mock<Promise<FeedProfileRow[]>, FindRowsArgs>;

/**
 * Tier selection is existence-based: a tier wins when a LIMITed fetch returns
 * a row, so no COUNT is issued anywhere on this path. The mock mirrors the
 * strategy's call order exactly — Tier 1's page fetch, then one `take: 1`
 * probe per wider tier in tier order, then the winning tier's page fetch.
 */
function buildStrategy(opts: {
  self?: typeof SELF | null;
  pref?: unknown;
  /** Candidates per tier, in tier order (index 0 = Tier 1). Any value above
   *  zero means that tier has someone; the number itself no longer matters. */
  tierCandidates: number[];
  rows?: FeedProfileRow[];
  config?: Partial<{
    enabled: boolean;
    ageRelaxStep1: number;
    ageRelaxStep2: number;
    maxTier: number;
  }>;
}) {
  // Kept so tests can assert it is NEVER called — the point of this design.
  const countMatching = jest.fn();

  const rows = opts.rows ?? [];
  const has = (tierIndex: number) => (opts.tierCandidates[tierIndex] ?? 0) > 0;

  const findRows: FindRowsMock = jest.fn<
    Promise<FeedProfileRow[]>,
    FindRowsArgs
  >();
  findRows.mockResolvedValueOnce(has(0) ? rows : []);
  if (!has(0)) {
    for (let i = 1; i < opts.tierCandidates.length; i++) {
      findRows.mockResolvedValueOnce(has(i) ? [makeRow(`tier${i + 1}`)] : []);
    }
    findRows.mockResolvedValueOnce(rows);
  }
  findRows.mockResolvedValue(rows);

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

/** The calls that fetched a page, as opposed to a `take: 1` existence probe. */
function pageFetches(findRows: FindRowsMock) {
  return findRows.mock.calls.filter(([, page]) => page.take !== 1);
}

describe('ProgressiveFallbackStrategy', () => {
  it('caller has no finalized profile: short-circuits to an empty feed with INCOMPLETE_SELF_PROFILE, running zero tier probes', async () => {
    const { strategy, countMatching, findRows } = buildStrategy({
      self: null,
      tierCandidates: [],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.rows).toEqual([]);
    expect(result.reason).toBe('INCOMPLETE_SELF_PROFILE');
    expect(result.fallbackUsed).toBe(false);
    // No pointless queries — the opposite-gender rule can't be met.
    expect(countMatching).not.toHaveBeenCalled();
    expect(findRows).not.toHaveBeenCalled();
  });

  it('exact match exists: Tier 1 returns immediately from ONE query, fallbackUsed=false', async () => {
    const { strategy, countMatching, findRows } = buildStrategy({
      tierCandidates: [4], // Tier 1 alone has candidates
      rows: [makeRow('a'), makeRow('b')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(1);
    expect(result.fallbackUsed).toBe(false);
    expect(result.rows).toHaveLength(2);
    // The whole point: one query, and never a COUNT.
    expect(findRows).toHaveBeenCalledTimes(1);
    expect(countMatching).not.toHaveBeenCalled();
    // Discover derives hasMore from the rows, so no total is produced.
    expect(result.total).toBeUndefined();
  });

  it('Tier 1 empty, Tier 2 has candidates: returns Tier 2 (lowest non-empty), fallbackUsed=true', async () => {
    const { strategy, countMatching, findRows } = buildStrategy({
      tierCandidates: [0, 3, 4, 5, 6, 7, 8, 9, 10, 11],
      rows: [makeRow('a'), makeRow('b'), makeRow('c')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(2);
    expect(result.fallbackUsed).toBe(true);
    expect(result.relaxedFilters).toEqual(['Age']);
    // On a Tier 1 miss, every wider tier is probed in ONE parallel batch (the
    // plan is monotonically relaxing, so the lowest-numbered non-empty tier is
    // the winner): Tier 1's fetch + 9 probes + the winner's fetch.
    expect(findRows).toHaveBeenCalledTimes(11);
    expect(pageFetches(findRows)).toHaveLength(2);
    expect(countMatching).not.toHaveBeenCalled();
  });

  it('Tier 1-2 empty, Tier 3 has candidates: returns Tier 3', async () => {
    const { strategy, findRows } = buildStrategy({
      tierCandidates: [0, 0, 6, 7, 8, 9, 10, 11, 12, 13],
      rows: [makeRow('a')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(3);
    expect(result.relaxedFilters).toEqual(['Age', 'City']);
    expect(findRows).toHaveBeenCalledTimes(11);
  });

  it('multiple wider tiers non-empty: the LOWEST-numbered one wins (guards the parallel-probe pick)', async () => {
    const { strategy, findRows } = buildStrategy({
      // Tiers 2-3 empty; tiers 4+ all have candidates. Tier 4 must win — not
      // whichever probe happens to resolve first.
      tierCandidates: [0, 0, 0, 7, 8, 9, 10, 11, 12, 20],
      rows: [makeRow('a')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(4);
    expect(result.relaxedFilters).toEqual(['Age', 'City', 'Caste']);
    // Tier 1's fetch and the winner's — not one page fetch per probed tier.
    expect(pageFetches(findRows)).toHaveLength(2);
  });

  it('Tier 10 returns users: every relaxation exhausted before the gender-only tier succeeds', async () => {
    const { strategy, findRows } = buildStrategy({
      tierCandidates: [0, 0, 0, 0, 0, 0, 0, 0, 0, 7],
      rows: [makeRow('a')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(10);
    expect(result.fallbackUsed).toBe(true);
    expect(findRows).toHaveBeenCalledTimes(11);
    // Tier 10's WHERE must still carry the shared eligibility, gender-only
    // query — status is a denylist (not an ACTIVE allowlist): PENDING_VERIFICATION
    // must remain visible even at the loosest tier (see eligibility.builder.ts).
    // Call 0 is Tier 1's fetch, calls 1-9 are the Tier 2-10 probes.
    const tier10Where = findRows.mock.calls[9][0];
    expect(JSON.stringify(tier10Where)).toContain(
      '"notIn":["SUSPENDED","DEACTIVATED","BANNED"]',
    );
  });

  it('every tier, Tier 1 included, carries the full shared eligibility', async () => {
    const { strategy, findRows } = buildStrategy({
      tierCandidates: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    });

    await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    const eligibility = buildEligibilityConditions({
      currentUserId: 'me',
      myGender: SELF.gender,
    });
    // Tier 1's fetch plus nine probes — every tier in the plan.
    expect(findRows).toHaveBeenCalledTimes(10);
    findRows.mock.calls.forEach(([where], index) => {
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
      tierCandidates: new Array(10).fill(0) as number[],
      rows: [],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(10);
    expect(result.rows).toEqual([]);
    expect(result.total).toBeUndefined();
  });

  it("pagination: skip/take are forwarded unchanged to the winning tier's row fetch", async () => {
    const { strategy, findRows } = buildStrategy({
      tierCandidates: [5],
      rows: [makeRow('a')],
    });

    await strategy.getFeedForUser('me', { skip: 40, take: 10 });

    expect(findRows).toHaveBeenCalledWith(
      expect.anything(),
      { skip: 40, take: 10 },
      'me',
    );
  });

  it('duplicate prevention: pages are fetched for Tier 1 and the winner only, never once per tier', async () => {
    const { strategy, findRows } = buildStrategy({
      tierCandidates: [0, 0, 0, 8],
      rows: [makeRow('a'), makeRow('b')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(pageFetches(findRows)).toHaveLength(2);
    // No duplicate ids possible from merging tiers — only one tier's rows are ever returned.
    const ids = result.rows.map((r) => (r as { userId: string }).userId);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('no COUNT is issued on any path — not on a hit, not on a full fallback', async () => {
    const hit = buildStrategy({ tierCandidates: [3], rows: [makeRow('a')] });
    await hit.strategy.getFeedForUser('me', { skip: 0, take: 20 });
    expect(hit.countMatching).not.toHaveBeenCalled();

    const fallback = buildStrategy({
      tierCandidates: [0, 0, 0, 0, 0, 0, 0, 0, 0, 4],
      rows: [makeRow('a')],
    });
    await fallback.strategy.getFeedForUser('me', { skip: 0, take: 20 });
    expect(fallback.countMatching).not.toHaveBeenCalled();
  });

  it('wider tiers are probed with take: 1 — existence, not a page of rows', async () => {
    const { strategy, findRows } = buildStrategy({
      tierCandidates: [0, 0, 5],
      rows: [makeRow('a')],
    });

    await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    const probes = findRows.mock.calls.filter(
      ([, page]) => (page as { take: number }).take === 1,
    );
    expect(probes).toHaveLength(9);
    probes.forEach(([, page]) => {
      expect(page).toEqual({ skip: 0, take: 1 });
    });
  });

  it('a non-empty Tier 1 paged past its end stays on Tier 1 rather than relaxing', async () => {
    // An empty WINDOW is not an empty TIER. Falling through here would relax a
    // member's preferences on a later page while the earlier ones were exact
    // matches, so the head is probed before any relaxation happens.
    const { strategy, countMatching, findRows } = buildStrategy({
      tierCandidates: [0],
      rows: [],
    });
    findRows.mockReset();
    // The requested window is past the end…
    findRows.mockResolvedValueOnce([]);
    // …but the tier itself has someone.
    findRows.mockResolvedValueOnce([makeRow('first')]);

    const result = await strategy.getFeedForUser('me', { skip: 40, take: 20 });

    expect(result.tier).toBe(1);
    expect(result.fallbackUsed).toBe(false);
    expect(result.rows).toHaveLength(0);
    // The page fetch plus the head probe — no wider tier was ever touched.
    expect(findRows).toHaveBeenCalledTimes(2);
    expect(findRows.mock.calls[1][1]).toEqual({ skip: 0, take: 1 });
    expect(countMatching).not.toHaveBeenCalled();
  });

  it('reading from the top needs no head probe — Discover never pays for it', async () => {
    const { strategy, findRows } = buildStrategy({
      tierCandidates: [0, 4],
      rows: [makeRow('a')],
    });

    await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    // Tier 1's fetch went straight to the wider probes: no take:1 probe against
    // Tier 1's own WHERE before them.
    expect(findRows.mock.calls[1][1]).toEqual({ skip: 0, take: 1 });
    expect(findRows.mock.calls[1][0]).not.toEqual(findRows.mock.calls[0][0]);
  });

  it('caller has no saved preference at all: only Tier 1 (gender-only) is tried, no fallback', async () => {
    const { strategy, countMatching, findRows } = buildStrategy({
      pref: null,
      tierCandidates: [9],
      rows: [makeRow('a')],
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(1);
    expect(result.fallbackUsed).toBe(false);
    expect(findRows).toHaveBeenCalledTimes(1);
    expect(countMatching).not.toHaveBeenCalled();
  });

  it('FALLBACK_ENABLED=false: stops after Tier 1 even if it is empty', async () => {
    const { strategy, findRows } = buildStrategy({
      tierCandidates: [0],
      rows: [],
      config: { enabled: false },
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    expect(result.tier).toBe(1);
    expect(findRows).toHaveBeenCalledTimes(1);
  });

  it('MAX_FALLBACK_TIER caps relaxation before Tier 10', async () => {
    const { strategy, findRows } = buildStrategy({
      tierCandidates: [0, 0, 0],
      rows: [],
      config: { maxTier: 3 },
    });

    const result = await strategy.getFeedForUser('me', { skip: 0, take: 20 });

    // Tier 1's fetch plus probes for Tiers 2 and 3 — nothing beyond the cap.
    expect(findRows).toHaveBeenCalledTimes(3);
    expect(result.tier).toBe(3); // last tier tried, per the configured ceiling
  });
});
