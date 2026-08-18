import { Injectable } from '@nestjs/common';
import type { FeedProfileRow } from '../repositories/feed.repository';
import type { CompatibilityBreakdown } from './compatibility.service';
import { isAfterCursor, type FeedCursor } from './feed-cursor';

/**
 * How a feed orders an already-scored, already-eligible candidate pool.
 *
 * This exists as its own service rather than a sort call inside FeedService
 * because the five feeds are about to want genuinely different orderings —
 * My Matches leads on the mutual half of the score, New leads on recency,
 * Daily wants the blended score — while sharing the same eligibility, the same
 * scoring, and the same pagination. Putting the ordering behind a named
 * strategy is what keeps that shared foundation from being copied five times.
 */
export type RankingStrategy = 'compatibility' | 'mutual' | 'recency';

export interface RankOptions {
  /** Candidate ids recently shown to this member — demoted, never removed. */
  seen?: Set<string>;
  /** When present, paging is by cursor and `skip` is ignored. */
  cursor?: FeedCursor | null;
}

export interface RankedCandidate {
  row: FeedProfileRow;
  score: CompatibilityBreakdown | undefined;
}

@Injectable()
export class RankingService {
  /**
   * Orders the pool and returns the requested slice.
   *
   * The sort is total and deterministic: score, then createdAt, then userId.
   * Without the final tie-break, two candidates with identical scores could
   * swap places between page 1 and page 2 of the same session — the classic
   * way a paginated feed shows a duplicate on one page and drops someone
   * entirely from the next. Every comparison below ends at userId for that
   * reason.
   */
  rank(
    candidates: RankedCandidate[],
    strategy: RankingStrategy,
    { skip, take }: { skip: number; take: number },
    options: RankOptions = {},
  ): RankedCandidate[] {
    const { seen, cursor } = options;

    // De-duplication happens BEFORE the sort, as a demotion rather than a
    // filter: a seen candidate keeps its score but sorts behind every unseen
    // one. Removing them outright would permanently hide people a member
    // merely scrolled past — see FeedSeenService.
    const ordered = [...candidates].sort((a, b) => {
      if (seen && seen.size > 0) {
        const aSeen = seen.has(this.idOf(a)) ? 1 : 0;
        const bSeen = seen.has(this.idOf(b)) ? 1 : 0;
        if (aSeen !== bSeen) return aSeen - bSeen;
      }
      return this.compare(a, b, strategy);
    });

    // Cursor paging: drop everything up to and including the previous page's
    // last item. Because the sort key is total, this lands on exactly one
    // boundary — no row can be both before and after it.
    if (cursor) {
      const after = ordered.filter((c) =>
        isAfterCursor(
          {
            score: this.keyScore(c, strategy),
            createdAt: this.createdAtOf(c),
            userId: this.idOf(c),
          },
          cursor,
        ),
      );
      return after.slice(0, take);
    }

    return ordered.slice(skip, skip + take);
  }

  /** The score the cursor compares against — must match the active strategy. */
  keyScore(c: RankedCandidate, strategy: RankingStrategy): number {
    if (strategy === 'recency') return 0;
    return strategy === 'mutual' ? this.mutualOf(c) : this.overallOf(c);
  }

  /** Builds the cursor for the last item of a page. */
  cursorFor(c: RankedCandidate, strategy: RankingStrategy): FeedCursor {
    return {
      score: this.keyScore(c, strategy),
      createdAt: this.createdAtOf(c),
      userId: this.idOf(c),
    };
  }

  private compare(
    a: RankedCandidate,
    b: RankedCandidate,
    strategy: RankingStrategy,
  ): number {
    if (strategy !== 'recency') {
      const primary =
        strategy === 'mutual'
          ? this.mutualOf(b) - this.mutualOf(a)
          : this.overallOf(b) - this.overallOf(a);
      if (primary !== 0) return primary;
    }

    // Newest first, both as the primary key for 'recency' and as the first
    // tie-break for the score-led strategies.
    const byDate = this.createdAtOf(b) - this.createdAtOf(a);
    if (byDate !== 0) return byDate;

    return this.idOf(a).localeCompare(this.idOf(b));
  }

  private overallOf(c: RankedCandidate): number {
    return c.score?.overall ?? 0;
  }

  /** Falls back to the blended score when the candidate saved no preference,
   *  so a member without preferences is ordered, not dumped at the bottom. */
  private mutualOf(c: RankedCandidate): number {
    return c.score?.mutualFit ?? c.score?.overall ?? 0;
  }

  createdAtOf(c: RankedCandidate): number {
    const v = (c.row as Record<string, unknown>).createdAt;
    return v instanceof Date ? v.getTime() : 0;
  }

  idOf(c: RankedCandidate): string {
    return String((c.row as Record<string, unknown>).userId ?? '');
  }
}
