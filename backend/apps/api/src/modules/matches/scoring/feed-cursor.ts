/**
 * Opaque cursor for the ranked feed.
 *
 * Why a cursor at all: offset paging asks the database for "rows 20-40 of the
 * current ordering", and that ordering shifts whenever anyone joins, edits a
 * profile, or gets blocked. A member paging through Discover then sees the same
 * profile twice and never sees another at all. A cursor names the exact
 * position instead of counting from the start, so a page boundary means the
 * same thing regardless of what changed underneath.
 *
 * The cursor encodes the whole sort key — score, createdAt, userId — because
 * that is exactly what RankingService orders by. Encoding only the id would be
 * ambiguous the moment two candidates share a score: there would be no way to
 * know which side of the boundary an equal-scoring row belongs on.
 *
 * Base64url of JSON rather than a signed token: this contains no secret and no
 * private data (a score and a uuid the caller was just shown), and an opaque
 * blob is enough to stop clients hand-building offsets and depending on the
 * ordering internals. It is validated on the way back in, so a malformed or
 * tampered cursor degrades to "start from the beginning" rather than throwing.
 */
export interface FeedCursor {
  /** Blended compatibility score of the last item on the previous page. */
  score: number;
  /** Its createdAt, as epoch milliseconds — first tie-break. */
  createdAt: number;
  /** Its userId — final tie-break, makes the key total. */
  userId: string;
}

export function encodeFeedCursor(cursor: FeedCursor): string {
  return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

/**
 * Returns null for anything that isn't a well-formed cursor — absent,
 * truncated, hand-edited, or from an older encoding. The caller treats null as
 * "first page", which is the safe degradation: a member gets a fresh page
 * rather than an error.
 */
export function decodeFeedCursor(raw: string | undefined | null): FeedCursor | null {
  if (!raw) return null;
  try {
    const parsed: unknown = JSON.parse(
      Buffer.from(raw, 'base64url').toString('utf8'),
    );
    if (!parsed || typeof parsed !== 'object') return null;
    const c = parsed as Record<string, unknown>;
    if (
      typeof c.score !== 'number' ||
      !Number.isFinite(c.score) ||
      typeof c.createdAt !== 'number' ||
      !Number.isFinite(c.createdAt) ||
      typeof c.userId !== 'string' ||
      c.userId.length === 0
    ) {
      return null;
    }
    return { score: c.score, createdAt: c.createdAt, userId: c.userId };
  } catch {
    return null;
  }
}

/**
 * True when `candidate` sorts strictly after `cursor` under the same ordering
 * RankingService applies: score descending, then createdAt descending, then
 * userId ascending.
 *
 * Kept next to the cursor rather than inside RankingService so the two can be
 * read together — if the sort ever changes, this comparison has to change with
 * it, and a reader should not have to find that out the hard way.
 */
export function isAfterCursor(
  candidate: { score: number; createdAt: number; userId: string },
  cursor: FeedCursor,
): boolean {
  if (candidate.score !== cursor.score) return candidate.score < cursor.score;
  if (candidate.createdAt !== cursor.createdAt) {
    return candidate.createdAt < cursor.createdAt;
  }
  return candidate.userId > cursor.userId;
}
