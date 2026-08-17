import { Injectable, Logger } from '@nestjs/common';
import { AppConfigService } from '@app/config';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { FeedRepository } from '../repositories/feed.repository';
import { PreferenceRepository } from '../repositories/preference.repository';
import type { SelfProfile } from '../repositories/feed.repository';
import {
  buildFeedWhere,
  type PreferenceFilters,
} from '../filters/partner-preference-where.builder';
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

    // No finalized profile → the caller's own gender is unknown, so the
    // mandatory opposite-gender rule can't be satisfied (buildFeedWhere fails
    // closed and every tier is guaranteed empty). Short-circuit with a stable,
    // machine-readable reason the client uses to prompt the user to finish
    // their profile — and skip the 10 pointless count probes.
    if (!self) {
      return {
        rows: [],
        total: 0,
        tier: 1,
        fallbackUsed: false,
        reason: 'INCOMPLETE_SELF_PROFILE',
        relaxedFilters: [],
      };
    }

    const myGender = self.gender;
    const config = this.configService.fallback;

    const plan = buildTierPlan(pref, {
      enabled: config.enabled,
      ageRelaxStep1: config.ageRelaxStep1,
      ageRelaxStep2: config.ageRelaxStep2,
      // Tier 1 always runs regardless of FALLBACK_ENABLED — only relaxation
      // (tier > 1) is gated by the flag.
      maxTier: config.enabled ? config.maxTier : 1,
    });

    const whereFor = (
      tierDef: TierDefinition,
    ): Prisma.UserProfileWhereInput => {
      const baseWhere = buildFeedWhere({
        currentUserId: userId,
        myGender,
        self,
        pref: tierDef.pref,
      });
      // Tier 1 mirrors the original engine exactly (no extra exclusions); the
      // widened tiers layer on the blocked/rejected/inactive safety filter.
      return tierDef.tier === 1
        ? baseWhere
        : withSafetyExclusions(baseWhere, userId);
    };

    // Tier 1 (the caller's exact saved preferences) is the overwhelmingly
    // common hit, so probe it alone first — the normal case pays exactly one
    // count + one row fetch and never touches the wider tiers.
    const tier1 = plan[0];
    const tier1Where = whereFor(tier1);
    const tier1Count = await this.feedRepository.countMatching(tier1Where);
    if (tier1Count > 0) {
      return this.page(tier1, tier1Where, tier1Count, { skip, take }, self, pref);
    }

    // Tier 1 was empty. The tier plan is *monotonically relaxing* — every
    // later tier matches a superset of the previous one — so the first
    // non-empty tier is simply the lowest-numbered tier whose count > 0.
    // That lets us probe every remaining tier's count in ONE parallel batch
    // instead of walking them one slow round trip at a time (the old path did
    // up to 9 sequential ~250-300ms COUNTs against Neon before giving up).
    const widerTiers = plan.slice(1);
    if (widerTiers.length === 0) {
      // No preferences to relax (caller has none saved) — Tier 1 was already
      // the loosest possible query, so an empty result is genuinely empty.
      return this.emptyFeed(tier1);
    }

    const widerWheres = widerTiers.map(whereFor);
    const counts = await Promise.all(
      widerWheres.map((where) => this.feedRepository.countMatching(where)),
    );
    const winnerIndex = counts.findIndex((count) => count > 0);

    if (winnerIndex === -1) {
      // Every tier up to the configured ceiling returned zero — an honest
      // empty feed, tagged with the loosest tier that was tried.
      this.logger.debug('No candidates at any tier — returning empty feed.');
      return this.emptyFeed(widerTiers[widerTiers.length - 1]);
    }

    this.logger.debug(`Returning Tier ${widerTiers[winnerIndex].tier}`);
    return this.page(
      widerTiers[winnerIndex],
      widerWheres[winnerIndex],
      counts[winnerIndex],
      { skip, take },
      self,
      pref,
    );
  }

  /** Fetches the page for a chosen tier and shapes the RecommendationResult. */
  private async page(
    tierDef: TierDefinition,
    where: Prisma.UserProfileWhereInput,
    total: number,
    { skip, take }: FeedPageQuery,
    seeker: SelfProfile,
    seekerPreference: PreferenceFilters | null,
  ): Promise<RecommendationResult> {
    const rows = await this.feedRepository.findRows(where, { skip, take });
    return {
      rows,
      total,
      seeker,
      seekerPreference,
      tier: tierDef.tier,
      fallbackUsed: tierDef.tier > 1,
      reason: tierDef.reason,
      relaxedFilters: tierDef.relaxedFilters,
    };
  }

  private emptyFeed(tierDef: TierDefinition): RecommendationResult {
    return {
      rows: [],
      total: 0,
      tier: tierDef.tier,
      fallbackUsed: tierDef.tier > 1,
      reason: 'No compatible profiles found.',
      relaxedFilters: tierDef.relaxedFilters,
    };
  }
}
