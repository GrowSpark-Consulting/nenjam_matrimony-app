import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { StorageModule } from '@app/storage';
import { DiscoverController } from './controllers/discover.controller';
import { FeedService } from './services/feed.service';
import { SearchService } from './services/search.service';
import { PreferencesService } from './services/preferences.service';
import { ProfileFeedMapper } from './mappers/profile-feed.mapper';
import { FeedRepository } from './repositories/feed.repository';
import { PreferenceRepository } from './repositories/preference.repository';
import { RECOMMENDATION_SERVICE } from './recommendation/recommendation.service';
import { FilteredFeedStrategy } from './recommendation/filtered-feed.strategy';
import { ProgressiveFallbackStrategy } from './recommendation/progressive-fallback.strategy';
import { SEARCH_STRATEGY } from './search/search.strategy';
import { PostgresSearchStrategy } from './search/postgres-search.strategy';

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
  imports: [StorageModule, AppConfigModule],
  controllers: [DiscoverController],
  providers: [
    FeedService,
    SearchService,
    PreferencesService,
    ProfileFeedMapper,
    FeedRepository,
    PreferenceRepository,
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
