import { Injectable, Logger } from '@nestjs/common';
import { AppConfigService } from '@app/config';
import { FeedRepository } from '../repositories/feed.repository';
import { PreferenceRepository } from '../repositories/preference.repository';
import { buildFeedWhere } from '../filters/partner-preference-where.builder';
import { withSafetyExclusions } from '../filters/safety-exclusions.builder';
import { buildTierPlan, TierDefinition } from './tier-plan';
import {
  FeedPageQuery,
  RecommendationResult,
  RecommendationService,
} from './recommendation.service';

/**
 * Production recommendation strategy: tries the caller's exact saved
 * preferences first (Tier 1 — identical query to the plain FilteredFeedStrategy,
 * via the same [buildFeedWhere]), and only if that returns zero candidates does
 * it progressively widen the search (see [buildTierPlan]) until it finds
 * matches or exhausts the configured tier ceiling. The first tier with
 * candidates wins — lower-relevance tiers are never reached once one succeeds.
 *
 * Tier 1 is deliberately built the exact same way FilteredFeedStrategy builds
 * it (same `buildFeedWhere` call, same inputs, no extra exclusions) — the
 * existing engine's behavior for a caller whose preferences already match
 * something is completely unchanged. The safety exclusions (blocked/rejected/
 * inactive — see [withSafetyExclusions]) only apply from Tier 2 onward, since
 * they are new behavior this strategy introduces, not part of the original
 * engine's contract.
 */
@Injectable()
export class ProgressiveFallbackStrategy implements RecommendationService {
  private readonly logger = new Logger(ProgressiveFallbackStrategy.name);

  constructor(
    private readonly feedRepository: FeedRepository,
    private readonly preferenceRepository: PreferenceRepository,
    private readonly configService: AppConfigService,
  ) {}

  async getFeedForUser(
    userId: string,
    { skip, take }: FeedPageQuery,
  ): Promise<RecommendationResult> {
    const [self, pref] = await Promise.all([
      this.feedRepository.findSelf(userId),
      this.preferenceRepository.findByUserId(userId),
    ]);
    const myGender = self?.gender ?? null;
    const config = this.configService.fallback;

    const plan = buildTierPlan(pref, {
      enabled: config.enabled,
      ageRelaxStep1: config.ageRelaxStep1,
      ageRelaxStep2: config.ageRelaxStep2,
      // Tier 1 always runs regardless of FALLBACK_ENABLED — only relaxation
      // (tier > 1) is gated by the flag.
      maxTier: config.enabled ? config.maxTier : 1,
    });

    let lastTier: TierDefinition = plan[0];

    for (const tierDef of plan) {
      lastTier = tierDef;
      const baseWhere = buildFeedWhere({
        currentUserId: userId,
        myGender,
        self,
        pref: tierDef.pref,
      });
      const where =
        tierDef.tier === 1 ? baseWhere : withSafetyExclusions(baseWhere, userId);

      const candidateCount = await this.feedRepository.countMatching(where);
      this.logger.log(`Tier ${tierDef.tier}\nCandidates: ${candidateCount}`);

      if (candidateCount > 0) {
        this.logger.log(`Returning Tier ${tierDef.tier}`);
        const rows = await this.feedRepository.findRows(where, { skip, take });
        return {
          rows,
          total: candidateCount,
          tier: tierDef.tier,
          fallbackUsed: tierDef.tier > 1,
          reason: tierDef.reason,
          relaxedFilters: tierDef.relaxedFilters,
        };
      }
    }

    // Every tier up to the configured ceiling returned zero — e.g. an empty
    // database, or no opposite-gender profiles exist at all. Not an error:
    // an honest empty feed, tagged with the loosest tier that was tried.
    this.logger.log('No candidates at any tier — returning empty feed.');
    return {
      rows: [],
      total: 0,
      tier: lastTier.tier,
      fallbackUsed: lastTier.tier > 1,
      reason: 'No compatible profiles found.',
      relaxedFilters: lastTier.relaxedFilters,
    };
  }
}
