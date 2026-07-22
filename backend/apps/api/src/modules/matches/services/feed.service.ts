import { Inject, Injectable } from '@nestjs/common';
import { DiscoverFeedResponseDto } from '../dto/discover-profile.response.dto';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import { RECOMMENDATION_SERVICE } from '../recommendation/recommendation.service';
import type { RecommendationService } from '../recommendation/recommendation.service';

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

    return {
      items: await this.mapper.toDtoList(result.rows),
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
