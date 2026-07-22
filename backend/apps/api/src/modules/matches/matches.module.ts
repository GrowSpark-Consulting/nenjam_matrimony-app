import { Module } from '@nestjs/common';
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
  imports: [StorageModule],
  controllers: [DiscoverController],
  providers: [
    FeedService,
    SearchService,
    PreferencesService,
    ProfileFeedMapper,
    FeedRepository,
    PreferenceRepository,
    // Phase 2 strategy bindings — the only lines that change when the
    // algorithm behind the feed/search evolves.
    { provide: RECOMMENDATION_SERVICE, useClass: FilteredFeedStrategy },
    { provide: SEARCH_STRATEGY, useClass: PostgresSearchStrategy },
    // Concrete strategies also registered so Nest can construct them.
    FilteredFeedStrategy,
    PostgresSearchStrategy,
  ],
})
export class MatchesModule {}
