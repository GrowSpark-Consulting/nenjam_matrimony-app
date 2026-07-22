import { Injectable } from '@nestjs/common';
import { FeedRepository } from '../repositories/feed.repository';
import { PreferenceRepository } from '../repositories/preference.repository';
import { buildFeedWhere } from '../filters/partner-preference-where.builder';
import {
  FeedPageQuery,
  RecommendationResult,
  RecommendationService,
} from './recommendation.service';

/**
 * Phase 2 recommendation strategy: deterministic partner-preference filtering,
 * no scoring or ranking. Loads the caller's gender + saved preference, builds a
 * dynamic WHERE (see [buildFeedWhere]) where unset preferences are ignored,
 * and returns the matching profiles newest-first.
 *
 * This is the whole "algorithm" today — Phase 4 replaces this class with an
 * AiRecommendationStrategy bound to the same RECOMMENDATION_SERVICE token.
 */
@Injectable()
export class FilteredFeedStrategy implements RecommendationService {
  constructor(
    private readonly feedRepository: FeedRepository,
    private readonly preferenceRepository: PreferenceRepository,
  ) {}

  async getFeedForUser(
    userId: string,
    { skip, take }: FeedPageQuery,
  ): Promise<RecommendationResult> {
    const [myGender, pref] = await Promise.all([
      this.feedRepository.findGender(userId),
      this.preferenceRepository.findByUserId(userId),
    ]);

    const where = buildFeedWhere({ currentUserId: userId, myGender, pref });
    return this.feedRepository.findMatching(where, { skip, take });
  }
}
