import {
  createCipheriv,
  createDecipheriv,
  createHmac,
  randomBytes,
} from 'node:crypto';

/**
 * Opaque, sealed cursor for the ranked feed.
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
 * It is SEALED (AES-256-GCM), not merely encoded, and bound to the member it
 * was issued to. The score in it is the ranking key, which includes the
 * marriage-compatibility refinement — information no member may read about
 * another. A plain base64 cursor would leak it on the way out (decode the last
 * item's score) and let a client probe it on the way in (hand-build a cursor at
 * a chosen score and see which side of it a candidate lands on, binary-searching
 * the exact value). Authenticated encryption closes both: the client can only
 * echo back a cursor the server issued, to the member it was issued to.
 *
 * A cursor that fails to open — malformed, tampered, another member's, from
 * before sealing existed, or sealed under a rotated secret — decodes to null,
 * and the caller treats null as "first page": a fresh page rather than an error.
 */
export interface FeedCursor {
  /** Ranking score of the last item on the previous page. */
  score: number;
  /** Its createdAt, as epoch milliseconds — first tie-break. */
  createdAt: number;
  /** Its userId — final tie-break, makes the key total. */
  userId: string;
}

const CURSOR_PREFIX = 'c1.';
const IV_BYTES = 12;
const TAG_BYTES = 16;

/** A purpose-bound key derived from the app secret, so the raw secret is never
 *  used directly as a cipher key and cursors can't be confused with anything
 *  else sealed under the same secret. */
export function deriveCursorKey(secret: string): Buffer {
  return createHmac('sha256', secret).update('nenjam:feed-cursor:v1').digest();
}

export function encodeFeedCursor(
  cursor: FeedCursor,
  key: Buffer,
  viewerId: string,
): string {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(Buffer.from(viewerId, 'utf8'));
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify(cursor), 'utf8'),
    cipher.final(),
  ]);
  return (
    CURSOR_PREFIX +
    Buffer.concat([iv, cipher.getAuthTag(), ciphertext]).toString('base64url')
  );
}

/**
 * Returns null for anything that isn't a cursor this server sealed for this
 * member — absent, truncated, hand-edited, unsealed, or from another member.
 */
export function decodeFeedCursor(
  raw: string | undefined | null,
  key: Buffer,
  viewerId: string,
): FeedCursor | null {
  if (!raw || !raw.startsWith(CURSOR_PREFIX)) return null;
  try {
    const bytes = Buffer.from(raw.slice(CURSOR_PREFIX.length), 'base64url');
    if (bytes.length <= IV_BYTES + TAG_BYTES) return null;
    const decipher = createDecipheriv(
      'aes-256-gcm',
      key,
      bytes.subarray(0, IV_BYTES),
    );
    decipher.setAAD(Buffer.from(viewerId, 'utf8'));
    decipher.setAuthTag(bytes.subarray(IV_BYTES, IV_BYTES + TAG_BYTES));
    const plain = Buffer.concat([
      decipher.update(bytes.subarray(IV_BYTES + TAG_BYTES)),
      decipher.final(),
    ]).toString('utf8');

    const parsed: unknown = JSON.parse(plain);
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
