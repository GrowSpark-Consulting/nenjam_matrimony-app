import type { PreferenceFilters } from '../filters/partner-preference-where.builder';
import type { SelfProfile } from '../repositories/feed.repository';
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
  /** Which tier produced these rows (1 = exact match on saved preferences).
   *  Strategies that don't implement tiered fallback can omit this — callers
   *  default it to 1/false/[] . */
  tier?: number;
  fallbackUsed?: boolean;
  reason?: string;
  relaxedFilters?: string[];
  /** The seeker's own profile and saved preference, as already loaded by the
   *  strategy while building the WHERE clause. Passed back so FeedService can
   *  score the page without re-fetching them — a second lookup here would add a
   *  full round trip to a request that already spends ~1s in its query stage. */
  seeker?: SelfProfile | null;
  seekerPreference?: PreferenceFilters | null;
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
