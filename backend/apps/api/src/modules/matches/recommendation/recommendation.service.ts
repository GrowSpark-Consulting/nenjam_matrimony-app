import type { FeedProfileRow } from '../repositories/feed.repository';

// DI token for the active recommendation strategy. FeedService depends only on
// this interface — never on a concrete strategy — so the algorithm behind the
// feed can change (Phase 2: filtering → Phase 4: AI ranking) without touching
// the controller, the service, or Flutter.
export const RECOMMENDATION_SERVICE = Symbol('RECOMMENDATION_SERVICE');

export interface FeedPageQuery {
  skip: number;
  take: number;
}

export interface RecommendationResult {
  rows: FeedProfileRow[];
  total: number;
}

export interface RecommendationService {
  /**
   * Returns the page of profiles this user should see, in whatever order the
   * strategy decides. Phase 2's FilteredFeedStrategy filters by partner
   * preference and returns them newest-first; a future AiRecommendationStrategy
   * would return the same rows scored/ranked — same signature either way.
   */
  getFeedForUser(
    userId: string,
    query: FeedPageQuery,
  ): Promise<RecommendationResult>;
}
