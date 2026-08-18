import { Inject, Injectable } from '@nestjs/common';
import { DiscoverFeedResponseDto } from '../dto/discover-profile.response.dto';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import { RECOMMENDATION_SERVICE } from '../recommendation/recommendation.service';
import type { RecommendationService } from '../recommendation/recommendation.service';
import { CompatibilityService } from '../scoring/compatibility.service';
import type { CompatibilityBreakdown } from '../scoring/compatibility.service';
import { toScorable } from '../scoring/scorable.mapper';
import { RankingService } from '../scoring/ranking.service';
import { FeedSeenService } from '../cache/feed-seen.cache';
import { FeedVersionService } from '../cache/feed-version.cache';
import { decodeFeedCursor, encodeFeedCursor } from '../scoring/feed-cursor';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

/**
 * How many eligible candidates are fetched and scored before the page is cut.
 *
 * Ranking by score is meaningless if the database has already chosen the 20
 * rows by a different key — the best match could sit at position 47 of the
 * newest-first order and never be scored at all. So the pool is deliberately
 * wider than the page.
 *
 * 200 is chosen from what the extra rows actually cost. Against this database
 * the row count barely moves the query: a bare `SELECT 1` measures p50 205ms
 * and p95 1044ms, so a request is dominated by round trips, not by fetching
 * 200 rows instead of 20 in the one trip it already makes. Scoring the wider
 * pool costs ~2ms.
 *
 * The limit it imposes: with a 20-row page this ranks correctly for the first
 * 10 pages. Beyond that the pool runs out and ordering degrades to the
 * database's own. Keyset pagination removes the ceiling properly and is the
 * next step; until then this covers far more than members actually page
 * through.
 */
const CANDIDATE_POOL = 200;

/**
 * Assembles the paginated Discover feed. It owns pagination + DTO mapping only
 * — it delegates "which profiles, in what order" to the injected
 * [RecommendationService], so it has no idea (and doesn't care) whether that's
 * preference filtering, AI ranking, or anything else. The API contract Flutter
 * consumes never changes as strategies evolve.
 */
@Injectable()
export class FeedService {
  constructor(
    @Inject(RECOMMENDATION_SERVICE)
    private readonly recommendation: RecommendationService,
    private readonly mapper: ProfileFeedMapper,
    private readonly compatibility: CompatibilityService,
    private readonly ranking: RankingService,
    private readonly seen: FeedSeenService,
    private readonly feedVersion: FeedVersionService,
  ) {}

  async getFeed(
    currentUserId: string,
    query: {
      page?: number;
      limit?: number;
      category?: string;
      cursor?: string;
    },
  ): Promise<DiscoverFeedResponseDto> {
    const page = Math.max(1, Number(query.page) || 1);
    const limit = Math.min(
      MAX_LIMIT,
      Math.max(1, Number(query.limit) || DEFAULT_LIMIT),
    );
    const skip = (page - 1) * limit;

    // Cursor paging is additive: when a cursor is supplied it takes over and
    // `page` is ignored, but every existing client that sends page/limit keeps
    // working unchanged. A malformed cursor decodes to null and simply starts
    // from the beginning rather than erroring.
    const cursor = decodeFeedCursor(query.cursor);

    // Fetch the pool from the top, not the page — the page is cut after
    // ranking, so asking the database for rows 20-40 of ITS ordering would
    // discard exactly the candidates ranking is meant to surface.
    const result = await this.recommendation.getFeedForUser(currentUserId, {
      skip: 0,
      take: Math.max(CANDIDATE_POOL, skip + limit),
    });

    // Scoring runs over the whole pool, not just the page — the page cannot be
    // chosen until every candidate has a score. It is pure in-memory work with
    // no I/O, measured at ~2ms for 200 candidates, against a request whose
    // network round trips cost hundreds of milliseconds each.
    //
    // `seeker` is absent only when the caller has no finalized profile, in
    // which case the feed is empty anyway and there is nothing to score.
    let scores: Map<string, CompatibilityBreakdown> | undefined;
    if (result.seeker && result.rows.length > 0) {
      scores = this.compatibility.scoreMany(
        toScorable(result.seeker as unknown as Record<string, unknown>),
        result.seekerPreference ?? null,
        result.rows.map((row) => toScorable(row)),
      );
    }

    // Order by score, then cut the page. When there is no seeker profile there
    // are no scores, and ranking falls through to the deterministic
    // createdAt/id order — identical to the previous behaviour.
    const strategy = scores ? 'compatibility' : 'recency';
    const candidates = result.rows.map((row) => ({
      row,
      score: scores?.get(String((row as Record<string, unknown>).userId ?? '')),
    }));

    // Recently-shown candidates are demoted so the four tabs don't all lead
    // with the same faces. Read failures return an empty set, in which case
    // the feed simply doesn't de-duplicate.
    // Seen-set and version are independent reads — issued together so the
    // response costs one Redis round trip, not two.
    const [seenIds, version] = await Promise.all([
      this.seen.get(currentUserId),
      this.feedVersion.get(currentUserId),
    ]);

    const ranked = this.ranking.rank(candidates, strategy, { skip, take: limit }, {
      seen: seenIds,
      cursor,
    });
    const pageRows = ranked.map((r) => r.row);

    // Record what was served. Deliberately not awaited: the response is
    // already assembled, and a member should never wait on bookkeeping.
    void this.seen.record(
      currentUserId,
      pageRows.map((r) => String((r as Record<string, unknown>).userId ?? '')),
    );

    const last = ranked.at(-1);
    const nextCursor =
      last && ranked.length === limit
        ? encodeFeedCursor(this.ranking.cursorFor(last, strategy))
        : null;

    return {
      items: await this.mapper.toDtoList(pageRows, scores),
      page,
      limit,
      total: result.total,
      hasMore: cursor
        ? nextCursor !== null
        : skip + pageRows.length < result.total,
      nextCursor,
      version,
      // A strategy that doesn't implement tiered fallback (e.g. the plain
      // FilteredFeedStrategy, or search reusing the same shape) simply omits
      // these — default to "no fallback happened".
      tier: result.tier ?? 1,
      fallbackUsed: result.fallbackUsed ?? false,
      reason: result.reason ?? '',
      relaxedFilters: result.relaxedFilters ?? [],
    };
  }
}
