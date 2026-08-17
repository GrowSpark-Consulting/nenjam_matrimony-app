import { Inject, Injectable } from '@nestjs/common';
import { DiscoverFeedResponseDto } from '../dto/discover-profile.response.dto';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import { RECOMMENDATION_SERVICE } from '../recommendation/recommendation.service';
import type { RecommendationService } from '../recommendation/recommendation.service';
import { CompatibilityService } from '../scoring/compatibility.service';
import type { CompatibilityBreakdown } from '../scoring/compatibility.service';
import { toScorable } from '../scoring/scorable.mapper';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

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
  ) {}

  async getFeed(
    currentUserId: string,
    query: { page?: number; limit?: number; category?: string },
  ): Promise<DiscoverFeedResponseDto> {
    const page = Math.max(1, Number(query.page) || 1);
    const limit = Math.min(
      MAX_LIMIT,
      Math.max(1, Number(query.limit) || DEFAULT_LIMIT),
    );
    const skip = (page - 1) * limit;

    const result = await this.recommendation.getFeedForUser(currentUserId, {
      skip,
      take: limit,
    });

    // Scoring runs over the page that was just fetched — at most `limit` rows,
    // never the whole candidate set — and is pure in-memory work with no I/O.
    // Measured at well under a millisecond for 20 rows against a query stage
    // that costs ~1s, so it does not move the request's latency.
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

    return {
      items: await this.mapper.toDtoList(result.rows, scores),
      page,
      limit,
      total: result.total,
      hasMore: skip + result.rows.length < result.total,
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
