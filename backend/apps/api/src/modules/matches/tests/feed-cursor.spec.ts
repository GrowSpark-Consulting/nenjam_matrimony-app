import {
  decodeFeedCursor,
  deriveCursorKey,
  encodeFeedCursor,
  isAfterCursor,
  type FeedCursor,
} from '../scoring/feed-cursor';
import { RankingService } from '../scoring/ranking.service';
import type { RankedCandidate } from '../scoring/ranking.service';
import type { CompatibilityBreakdown } from '../scoring/compatibility.service';

const CURSOR: FeedCursor = { score: 80, createdAt: 1_700_000_000_000, userId: 'u5' };
const KEY = deriveCursorKey('a-test-secret-of-sufficient-length');
const VIEWER = 'viewer-1';
const seal = (c: FeedCursor = CURSOR): string => encodeFeedCursor(c, KEY, VIEWER);
const open = (raw: string | undefined | null): FeedCursor | null =>
  decodeFeedCursor(raw, KEY, VIEWER);

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
    expect(open(seal())).toEqual(CURSOR);
  });

  it('is opaque — not readable as plain JSON', () => {
    expect(seal()).not.toContain('userId');
  });

  describe('is sealed: the ranking score can be neither read out nor probed in', () => {
    const decodeBase64Json = (raw: string) =>
      Buffer.from(raw.replace(/^c1./, ''), 'base64url').toString('utf8');

    it('does not contain the score, timestamp or user id in any decodable form', () => {
      const sealed = seal({
        score: 87.35,
        createdAt: 1_700_000_000_000,
        userId: 'candidate-42',
      });
      const decoded = decodeBase64Json(sealed);
      for (const secret of ['87.35', '1700000000000', 'candidate-42']) {
        expect(sealed).not.toContain(secret);
        expect(decoded).not.toContain(secret);
      }
    });

    it('is different every time for the same cursor (random IV)', () => {
      expect(seal()).not.toBe(seal());
    });

    it('rejects a hand-built plain cursor — the old format can no longer be forged', () => {
      const plain = Buffer.from(JSON.stringify(CURSOR)).toString('base64url');
      expect(open(plain)).toBeNull();
      expect(open('c1.' + plain)).toBeNull();
    });

    it('rejects a cursor with any byte changed', () => {
      const sealed = seal();
      const bytes = Buffer.from(sealed.slice(3), 'base64url');
      for (const index of [0, 13, bytes.length - 1]) {
        const tampered = Buffer.from(bytes);
        tampered[index] ^= 1;
        expect(open('c1.' + tampered.toString('base64url'))).toBeNull();
      }
    });

    it('rejects a truncated cursor', () => {
      expect(open(seal().slice(0, 20))).toBeNull();
    });

    it('is bound to the member it was issued to', () => {
      expect(decodeFeedCursor(seal(), KEY, 'someone-else')).toBeNull();
    });

    it('is bound to the server secret', () => {
      const other = deriveCursorKey('a-different-secret-entirely-here');
      expect(decodeFeedCursor(seal(), other, VIEWER)).toBeNull();
    });
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
      expect(open(input)).toBeNull();
    });
  });

  describe('a sealed payload that is not a valid cursor is still rejected', () => {
    it.each([
      ['missing userId', { score: 1, createdAt: 2 }],
      ['wrong types', { score: 'x', createdAt: 2, userId: 'a' }],
      ['null score', { score: null, createdAt: 2, userId: 'a' }],
      ['empty userId', { score: 1, createdAt: 2, userId: '' }],
    ])('%s → null', (_label, payload) => {
      expect(open(seal(payload as unknown as FeedCursor))).toBeNull();
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
