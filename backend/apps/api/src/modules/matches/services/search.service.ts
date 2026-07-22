import { Inject, Injectable } from '@nestjs/common';
import { DiscoverFeedResponseDto } from '../dto/discover-profile.response.dto';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import { SEARCH_STRATEGY } from '../search/search.strategy';
import type { SearchStrategy } from '../search/search.strategy';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

/**
 * Text search over profiles. Owns pagination + DTO mapping (identical envelope
 * to the feed, so Flutter reuses the same parsing); the actual matching is
 * delegated to the injected [SearchStrategy] — Postgres today, Elasticsearch
 * later, with no change here.
 */
@Injectable()
export class SearchService {
  constructor(
    @Inject(SEARCH_STRATEGY) private readonly strategy: SearchStrategy,
    private readonly mapper: ProfileFeedMapper,
  ) {}

  async search(
    currentUserId: string,
    q: string,
    query: { page?: number; limit?: number },
  ): Promise<DiscoverFeedResponseDto> {
    const page = Math.max(1, Number(query.page) || 1);
    const limit = Math.min(
      MAX_LIMIT,
      Math.max(1, Number(query.limit) || DEFAULT_LIMIT),
    );
    const skip = (page - 1) * limit;

    const { rows, total } = await this.strategy.search(currentUserId, q ?? '', {
      skip,
      take: limit,
    });

    return {
      items: await this.mapper.toDtoList(rows),
      page,
      limit,
      total,
      hasMore: skip + rows.length < total,
    };
  }
}
