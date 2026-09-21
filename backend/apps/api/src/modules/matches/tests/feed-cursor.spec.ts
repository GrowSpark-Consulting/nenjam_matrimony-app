import {
  decodeFeedCursor,
  encodeFeedCursor,
  isAfterCursor,
  type FeedCursor,
} from '../scoring/feed-cursor';
import { RankingService } from '../scoring/ranking.service';
import type { RankedCandidate } from '../scoring/ranking.service';
import type { CompatibilityBreakdown } from '../scoring/compatibility.service';

const CURSOR: FeedCursor = { score: 80, createdAt: 1_700_000_000_000, userId: 'u5' };

function candidate(
  userId: string,
  overall: number,
  createdAt = new Date('2026-01-01'),
): RankedCandidate {
  const score: CompatibilityBreakdown = {
    seekerFit: overall,
    mutualFit: null,
    overall,
    band: 'Good',
    components: [],
    matchedPreferences: [],
    unmatchedPreferences: [],
    algorithmVersion: 'v1-preference',
  };
  return { row: { userId, createdAt } as unknown as RankedCandidate['row'], score };
}

const ids = (rs: RankedCandidate[]): string[] =>
  rs.map((r) => String((r.row as Record<string, unknown>).userId));

describe('feed cursor', () => {
  it('round-trips exactly', () => {
    expect(decodeFeedCursor(encodeFeedCursor(CURSOR))).toEqual(CURSOR);
  });

  it('is opaque — not readable as plain JSON', () => {
    expect(encodeFeedCursor(CURSOR)).not.toContain('userId');
  });

  describe('rejects anything malformed, degrading to "first page"', () => {
    it.each([
      ['undefined', undefined],
      ['empty', ''],
      ['not base64', '!!!!'],
      ['base64 of non-JSON', Buffer.from('hello').toString('base64url')],
      ['JSON missing userId', Buffer.from(JSON.stringify({ score: 1, createdAt: 2 })).toString('base64url')],
      ['JSON with wrong types', Buffer.from(JSON.stringify({ score: 'x', createdAt: 2, userId: 'a' })).toString('base64url')],
      ['NaN score', Buffer.from(JSON.stringify({ score: null, createdAt: 2, userId: 'a' })).toString('base64url')],
    ])('%s → null', (_label, input) => {
      expect(decodeFeedCursor(input as string | undefined)).toBeNull();
    });
  });

  describe('boundary comparison matches the ranking order', () => {
    it('a lower score sorts after', () => {
      expect(isAfterCursor({ score: 70, createdAt: CURSOR.createdAt, userId: 'a' }, CURSOR)).toBe(true);
    });
    it('a higher score sorts before', () => {
      expect(isAfterCursor({ score: 90, createdAt: CURSOR.createdAt, userId: 'a' }, CURSOR)).toBe(false);
    });
    it('equal score falls back to createdAt, newest first', () => {
      expect(isAfterCursor({ score: 80, createdAt: CURSOR.createdAt - 1, userId: 'a' }, CURSOR)).toBe(true);
      expect(isAfterCursor({ score: 80, createdAt: CURSOR.createdAt + 1, userId: 'a' }, CURSOR)).toBe(false);
    });
    it('equal score and date fall back to id', () => {
      expect(isAfterCursor({ ...CURSOR, userId: 'u6' }, CURSOR)).toBe(true);
      expect(isAfterCursor({ ...CURSOR, userId: 'u4' }, CURSOR)).toBe(false);
    });
    it('the cursor item itself is never re-served', () => {
      expect(isAfterCursor({ ...CURSOR }, CURSOR)).toBe(false);
    });
  });
});

describe('RankingService with cursor and seen', () => {
  let svc: RankingService;
  beforeEach(() => {
    svc = new RankingService();
  });

  it('pages through the whole set with no duplicates and no gaps', () => {
    const pool = Array.from({ length: 25 }, (_, i) => candidate(`u${i}`, 100 - i));
    const collected: string[] = [];
    let cursor: FeedCursor | null = null;

    for (let guard = 0; guard < 10; guard++) {
      const page = svc.rank(pool, 'compatibility', { skip: 0, take: 10 }, { cursor });
      if (page.length === 0) break;
      collected.push(...ids(page));
      const last = page.at(-1)!;
      cursor = svc.cursorFor(last, 'compatibility');
      if (page.length < 10) break;
    }

    expect(collected).toHaveLength(25);
    expect(new Set(collected).size).toBe(25);
  });

  it('is stable when a new candidate is inserted mid-paging', () => {
    // The classic offset bug: a new arrival shifts everything down and page 2
    // repeats an item from page 1. A cursor names a position, so it cannot.
    const pool = Array.from({ length: 20 }, (_, i) => candidate(`u${i}`, 100 - i));
    const page1 = svc.rank(pool, 'compatibility', { skip: 0, take: 5 }, { cursor: null });
    const cursor = svc.cursorFor(page1.at(-1)!, 'compatibility');

    // Someone new joins with the top score.
    const grown = [candidate('newcomer', 999), ...pool];
    const page2 = svc.rank(grown, 'compatibility', { skip: 0, take: 5 }, { cursor });

    expect(ids(page2).some((id) => ids(page1).includes(id))).toBe(false);
    expect(ids(page2)).not.toContain('newcomer');
  });

  it('demotes seen candidates without removing them', () => {
    const pool = [candidate('seen', 100), candidate('fresh', 10)];
    const page = svc.rank(pool, 'compatibility', { skip: 0, take: 10 }, {
      seen: new Set(['seen']),
    });
    // Still present — just last.
    expect(ids(page)).toEqual(['fresh', 'seen']);
  });

  it('still returns seen candidates when everything has been seen', () => {
    const pool = [candidate('a', 90), candidate('b', 80)];
    const page = svc.rank(pool, 'compatibility', { skip: 0, take: 10 }, {
      seen: new Set(['a', 'b']),
    });
    // An empty feed would be the wrong answer — a member who has scrolled
    // through everything should see it again, not nothing.
    expect(ids(page)).toEqual(['a', 'b']);
  });

  it('orders unseen by score, then seen by score', () => {
    const pool = [
      candidate('seen-high', 95),
      candidate('unseen-low', 20),
      candidate('seen-low', 30),
      candidate('unseen-high', 60),
    ];
    const page = svc.rank(pool, 'compatibility', { skip: 0, take: 10 }, {
      seen: new Set(['seen-high', 'seen-low']),
    });
    expect(ids(page)).toEqual(['unseen-high', 'unseen-low', 'seen-high', 'seen-low']);
  });

  it('falls back to offset paging when no cursor is supplied', () => {
    const pool = Array.from({ length: 10 }, (_, i) => candidate(`u${i}`, 100 - i));
    expect(ids(svc.rank(pool, 'compatibility', { skip: 5, take: 3 }))).toEqual(['u5', 'u6', 'u7']);
  });
});
