import { Injectable, Logger } from '@nestjs/common';
import { AppConfigService } from '@app/config';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { FeedRepository } from '../repositories/feed.repository';
import { PreferenceRepository } from '../repositories/preference.repository';
import { FeedContextService } from '../cache/feed-context.cache';
import type { SelfProfile } from '../repositories/feed.repository';
import {
  buildFeedWhere,
  type PreferenceFilters,
} from '../filters/partner-preference-where.builder';
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
 * This is the feed's candidate generation. Every tier's WHERE is built by
 * [buildFeedWhere]: the shared hard eligibility (see eligibility.builder.ts)
 * plus that tier's preference. Tiers differ only in the preference half.
 */
@Injectable()
export class ProgressiveFallbackStrategy implements RecommendationService {
  private readonly logger = new Logger(ProgressiveFallbackStrategy.name);

  constructor(
    private readonly feedRepository: FeedRepository,
    private readonly preferenceRepository: PreferenceRepository,
    private readonly configService: AppConfigService,
    private readonly feedContext: FeedContextService,
  ) {}

  async getFeedForUser(
    userId: string,
    { skip, take }: FeedPageQuery,
  ): Promise<RecommendationResult> {
    // The seeker's own profile and preference, served from Redis when warm.
    // On a hit this removes a whole sequential round trip from the request; on
    // a miss (or with Redis down) FeedContextService performs exactly the same
    // parallel pair of queries this line used to, so behaviour is unchanged
    // either way. Nothing safety-critical is cached — blocks, declined
    // interests, account status and deletedAt are still evaluated live inside
    // buildFeedWhere below.
    const { self, pref } = await this.feedContext.load(userId);

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

    // Every tier is the same hard eligibility plus that tier's (relaxed)
    // preference. Relaxation only ever touches the preference half, so no tier
    // — not even Tier 10 — can surface someone eligibility excludes.
    const whereFor = (tierDef: TierDefinition): Prisma.UserProfileWhereInput =>
      buildFeedWhere({
        currentUserId: userId,
        myGender,
        self,
        pref: tierDef.pref,
      });

    // Tier 1 (the caller's exact saved preferences) is the overwhelmingly
    // common hit, so probe it alone first — the normal case pays exactly one
    // count + one row fetch and never touches the wider tiers.
    const tier1 = plan[0];
    const tier1Where = whereFor(tier1);

    // Tier 1's count and its rows are issued TOGETHER, not one after the other.
    //
    // They are independent queries against the same WHERE, and a round trip to
    // this database costs ~250ms — so awaiting the count first made the common
    // request (Tier 1 hits for almost everyone) pay two sequential trips where
    // one would do. Overlapping them removes a whole trip from the hot path.
    //
    // The cost of that: when Tier 1 turns out to be empty, its row fetch was
    // wasted. That fetch returns no rows, so it transfers nothing and stops at
    // the same point the count does — a cheap query on the rare path, traded
    // for a saved round trip on the common one.
    //
    // The count still decides the tier, not the row count: with `skip` past the
    // end of a non-empty tier the fetch legitimately returns nothing, and
    // falling through to the wider tiers there would quietly relax someone's
    // preferences on page 3 while pages 1-2 were exact.
    const [tier1Count, tier1Rows] = await Promise.all([
      this.feedRepository.countMatching(tier1Where),
      this.feedRepository.findRows(tier1Where, { skip, take }, self.userId),
    ]);
    if (tier1Count > 0) {
      return {
        rows: tier1Rows,
        total: tier1Count,
        seeker: self,
        seekerPreference: pref,
        tier: tier1.tier,
        fallbackUsed: false,
        reason: tier1.reason,
        relaxedFilters: tier1.relaxedFilters,
      };
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
    const rows = await this.feedRepository.findRows(
      where,
      { skip, take },
      seeker.userId,
    );
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
