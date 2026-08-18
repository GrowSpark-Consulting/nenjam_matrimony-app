import { RankingService } from '../scoring/ranking.service';
import type { RankedCandidate } from '../scoring/ranking.service';
import type { CompatibilityBreakdown } from '../scoring/compatibility.service';

function breakdown(overall: number, mutualFit: number | null = null): CompatibilityBreakdown {
  return { seekerFit: overall, mutualFit, overall, band: 'Good', components: [] };
}

function candidate(
  userId: string,
  overall: number | undefined,
  createdAt = new Date('2026-01-01'),
  mutualFit: number | null = null,
): RankedCandidate {
  return {
    row: { userId, createdAt } as unknown as RankedCandidate['row'],
    score: overall === undefined ? undefined : breakdown(overall, mutualFit),
  };
}

describe('RankingService', () => {
  let svc: RankingService;
  beforeEach(() => {
    svc = new RankingService();
  });

  const ids = (rs: RankedCandidate[]): string[] =>
    rs.map((r) => String((r.row as Record<string, unknown>).userId));

  it('orders by compatibility score, highest first', () => {
    const pool = [candidate('a', 72), candidate('b', 94), candidate('c', 61), candidate('d', 88)];
    expect(ids(svc.rank(pool, 'compatibility', { skip: 0, take: 4 }))).toEqual(['b', 'd', 'a', 'c']);
  });

  it('breaks score ties by recency, then by id — never arbitrarily', () => {
    const older = new Date('2026-01-01');
    const newer = new Date('2026-06-01');
    const pool = [
      candidate('zzz', 80, older),
      candidate('aaa', 80, older),
      candidate('mmm', 80, newer),
    ];
    // Newest first; the two same-date entries fall back to id order.
    expect(ids(svc.rank(pool, 'compatibility', { skip: 0, take: 3 }))).toEqual(['mmm', 'aaa', 'zzz']);
  });

  it('produces a stable order across repeated runs of a shuffled pool', () => {
    const pool = [
      candidate('a', 80), candidate('b', 80), candidate('c', 80),
      candidate('d', 80), candidate('e', 80),
    ];
    const first = ids(svc.rank(pool, 'compatibility', { skip: 0, take: 5 }));
    for (let i = 0; i < 20; i++) {
      const shuffled = [...pool].sort(() => Math.random() - 0.5);
      expect(ids(svc.rank(shuffled, 'compatibility', { skip: 0, take: 5 }))).toEqual(first);
    }
  });

  it('paginates without duplicating or dropping a candidate', () => {
    const pool = Array.from({ length: 25 }, (_, i) => candidate(`u${i}`, 100 - i));
    const p1 = ids(svc.rank(pool, 'compatibility', { skip: 0, take: 10 }));
    const p2 = ids(svc.rank(pool, 'compatibility', { skip: 10, take: 10 }));
    const p3 = ids(svc.rank(pool, 'compatibility', { skip: 20, take: 10 }));
    const all = [...p1, ...p2, ...p3];
    expect(new Set(all).size).toBe(25);
    expect(all).toHaveLength(25);
  });

  it('does not mutate the pool it was given', () => {
    const pool = [candidate('a', 10), candidate('b', 90)];
    const before = ids(pool);
    svc.rank(pool, 'compatibility', { skip: 0, take: 2 });
    expect(ids(pool)).toEqual(before);
  });

  it('ranks by the mutual half when asked, not the blended score', () => {
    // 'a' blends higher overall, 'b' is the stronger two-way match.
    const pool = [candidate('a', 90, new Date('2026-01-01'), 40), candidate('b', 70, new Date('2026-01-01'), 95)];
    expect(ids(svc.rank(pool, 'compatibility', { skip: 0, take: 2 }))).toEqual(['a', 'b']);
    expect(ids(svc.rank(pool, 'mutual', { skip: 0, take: 2 }))).toEqual(['b', 'a']);
  });

  it('falls back to recency when no candidate has a score', () => {
    const pool = [
      candidate('old', undefined, new Date('2020-01-01')),
      candidate('new', undefined, new Date('2026-01-01')),
    ];
    expect(ids(svc.rank(pool, 'recency', { skip: 0, take: 2 }))).toEqual(['new', 'old']);
  });

  it('places unscored candidates below scored ones rather than crashing', () => {
    const pool = [candidate('scored', 50), candidate('unscored', undefined)];
    expect(ids(svc.rank(pool, 'compatibility', { skip: 0, take: 2 }))).toEqual(['scored', 'unscored']);
  });

  it('returns an empty page when the pool is exhausted', () => {
    const pool = [candidate('a', 90)];
    expect(svc.rank(pool, 'compatibility', { skip: 50, take: 20 })).toEqual([]);
  });
});
