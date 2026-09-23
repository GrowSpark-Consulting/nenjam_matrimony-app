import { Injectable, Logger } from '@nestjs/common';
import { AppConfigService } from '@app/config';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { FeedRepository } from '../repositories/feed.repository';
import { PreferenceRepository } from '../repositories/preference.repository';
import { FeedContextService } from '../cache/feed-context.cache';
import type {
  FeedProfileRow,
  SelfProfile,
} from '../repositories/feed.repository';
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

    // ONE query on the common path: the page fetch IS Tier 1's probe.
    //
    // Tier selection only ever needed the answer to "does this tier have
    // anyone?", and a COUNT is an expensive way to ask it — it scans every
    // matching row to produce a number the Discover client never reads. A
    // LIMITed fetch answers the same question and stops as soon as it has
    // enough rows, so asking and fetching became the same query.
    const tier1Rows = await this.feedRepository.findRows(
      tier1Where,
      { skip, take },
      self.userId,
    );
    if (tier1Rows.length > 0) {
      return this.result(tier1, tier1Rows, self, pref);
    }

    // An empty window is not the same as an empty tier: a caller paging past
    // the end of a perfectly good Tier 1 lands here too, and relaxing their
    // preferences at that point would widen page 3 while pages 1-2 were exact
    // matches. One cheap head probe separates the two cases. Discover always
    // reads from the top (FeedService fetches the pool at offset 0 and pages
    // in memory), so this costs nothing on that path.
    if (skip > 0) {
      const head = await this.feedRepository.findRows(
        tier1Where,
        { skip: 0, take: 1 },
        self.userId,
      );
      if (head.length > 0) return this.result(tier1, [], self, pref);
    }

    // Tier 1 was empty. The tier plan is *monotonically relaxing* — every
    // later tier matches a superset of the previous one — so the first
    // non-empty tier is simply the lowest-numbered tier that returns a row.
    // All of them are probed in ONE parallel batch instead of walking them a
    // slow round trip at a time (the old path did up to 9 sequential
    // ~250-300ms queries against Neon before giving up).
    //
    // `take: 1` is the whole probe: existence is all tier selection ever asks,
    // and a single row is the cheapest possible answer — the database stops at
    // the first match instead of counting every one of them.
    const widerTiers = plan.slice(1);
    if (widerTiers.length === 0) {
      // No preferences to relax (caller has none saved) — Tier 1 was already
      // the loosest possible query, so an empty result is genuinely empty.
      return this.emptyFeed(tier1);
    }

    const widerWheres = widerTiers.map(whereFor);
    const probes = await Promise.all(
      widerWheres.map((where) =>
        this.feedRepository.findRows(where, { skip: 0, take: 1 }, self.userId),
      ),
    );
    const winnerIndex = probes.findIndex((rows) => rows.length > 0);

    if (winnerIndex === -1) {
      // Every tier up to the configured ceiling returned nothing — an honest
      // empty feed, tagged with the loosest tier that was tried.
      this.logger.debug('No candidates at any tier — returning empty feed.');
      return this.emptyFeed(widerTiers[widerTiers.length - 1]);
    }

    this.logger.debug(`Returning Tier ${widerTiers[winnerIndex].tier}`);
    return this.page(
      widerTiers[winnerIndex],
      widerWheres[winnerIndex],
      { skip, take },
      self,
      pref,
    );
  }

  /** Fetches the page for a chosen tier and shapes the RecommendationResult. */
  private async page(
    tierDef: TierDefinition,
    where: Prisma.UserProfileWhereInput,
    { skip, take }: FeedPageQuery,
    seeker: SelfProfile,
    seekerPreference: PreferenceFilters | null,
  ): Promise<RecommendationResult> {
    const rows = await this.feedRepository.findRows(
      where,
      { skip, take },
      seeker.userId,
    );
    return this.result(tierDef, rows, seeker, seekerPreference);
  }

  /** The RecommendationResult for a tier that won, with its rows already in
   *  hand. No `total`: Discover derives `hasMore` from the rows themselves. */
  private result(
    tierDef: TierDefinition,
    rows: FeedProfileRow[],
    seeker: SelfProfile,
    seekerPreference: PreferenceFilters | null,
  ): RecommendationResult {
    return {
      rows,
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
      tier: tierDef.tier,
      fallbackUsed: tierDef.tier > 1,
      reason: 'No compatible profiles found.',
      relaxedFilters: tierDef.relaxedFilters,
    };
  }
}
