import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { StorageModule } from '@app/storage';
import { InterestsModule } from '../interests/interests.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PsychologyModule } from '../psychology/psychology.module';
import { EntitlementsModule } from '../entitlements/entitlements.module';
import { DiscoverController } from './controllers/discover.controller';
import { NearbyController } from './controllers/nearby.controller';
import { MatchesController } from './controllers/matches.controller';
import { FeedService } from './services/feed.service';
import { NearbyService } from './services/nearby.service';
import { SearchService } from './services/search.service';
import { ProfileLookupService } from './services/profile-lookup.service';
import { PreferencesService } from './services/preferences.service';
import { ShortlistService } from './services/shortlist.service';
import { ProfileViewService } from './services/profile-view.service';
import { ProfileFeedMapper } from './mappers/profile-feed.mapper';
import { FeedRepository } from './repositories/feed.repository';
import { NearbyRepository } from './repositories/nearby.repository';
import { PreferenceRepository } from './repositories/preference.repository';
import { ShortlistRepository } from './repositories/shortlist.repository';
import { ProfileViewRepository } from './repositories/profile-view.repository';
import { RECOMMENDATION_SERVICE } from './recommendation/recommendation.service';
import { FilteredFeedStrategy } from './recommendation/filtered-feed.strategy';
import { ProgressiveFallbackStrategy } from './recommendation/progressive-fallback.strategy';
import { SEARCH_STRATEGY } from './search/search.strategy';
import { CompatibilityService } from './scoring/compatibility.service';
import { FeedContextService } from './cache/feed-context.cache';
import { FeedSeenService } from './cache/feed-seen.cache';

import { RankingService } from './scoring/ranking.service';
import { PostgresSearchStrategy } from './search/postgres-search.strategy';
import { PsychologyMatchContextService } from './scoring/psychology/psychology-match-context.service';

/**
 * Discover: preference-filtered feed + text search + partner-preference CRUD.
 *
 * The active recommendation/search algorithms are bound to interface tokens
 * (RECOMMENDATION_SERVICE, SEARCH_STRATEGY), so swapping in an AI recommender
 * or an Elasticsearch backend later is a one-line change here — no controller,
 * service, or Flutter change. PrismaService is global; StorageModule is
 * imported for presigning photo URLs.
 */
@Module({
  imports: [
    StorageModule,
    AppConfigModule,
    InterestsModule,
    NotificationsModule,
    // Exports only PsychologyRepository (read-only quiz/response lookups for
    // live scoring, see PsychologyMatchContextService) — one-directional,
    // psychology never imports matches.
    PsychologyModule,
    // The plan-based shortlist cap (ShortlistService).
    EntitlementsModule,
  ],
  controllers: [DiscoverController, MatchesController, NearbyController],
  providers: [
    CompatibilityService,
    FeedContextService,
    FeedSeenService,
    RankingService,
    PsychologyMatchContextService,
    FeedService,
    NearbyService,
    SearchService,
    ProfileLookupService,
    PreferencesService,
    ShortlistService,
    ProfileViewService,
    ProfileFeedMapper,
    FeedRepository,
    NearbyRepository,
    PreferenceRepository,
    ShortlistRepository,
    ProfileViewRepository,
    // Strategy bindings — the only lines that change when the algorithm
    // behind the feed/search evolves. ProgressiveFallbackStrategy is Tier 1
    // (FilteredFeedStrategy's exact `buildFeedWhere` query) plus progressive
    // relaxation tiers 2-10 when Tier 1 returns zero — see tier-plan.ts.
    // FilteredFeedStrategy itself stays registered/available: it's the
    // reference "strict only" implementation this strategy is built on top
    // of, not removed or replaced.
    { provide: RECOMMENDATION_SERVICE, useClass: ProgressiveFallbackStrategy },
    { provide: SEARCH_STRATEGY, useClass: PostgresSearchStrategy },
    // Concrete strategies also registered so Nest can construct them.
    FilteredFeedStrategy,
    ProgressiveFallbackStrategy,
    PostgresSearchStrategy,
  ],
})
export class MatchesModule {}
