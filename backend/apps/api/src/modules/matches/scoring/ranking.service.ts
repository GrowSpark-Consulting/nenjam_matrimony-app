import { Injectable } from '@nestjs/common';
import type { FeedProfileRow } from '../repositories/feed.repository';
import type { CompatibilityBreakdown } from './compatibility.service';

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
  ): RankedCandidate[] {
    const ordered = [...candidates].sort((a, b) => this.compare(a, b, strategy));
    return ordered.slice(skip, skip + take);
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

  private createdAtOf(c: RankedCandidate): number {
    const v = (c.row as Record<string, unknown>).createdAt;
    return v instanceof Date ? v.getTime() : 0;
  }

  private idOf(c: RankedCandidate): string {
    return String((c.row as Record<string, unknown>).userId ?? '');
  }
}
