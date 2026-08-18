import { Global, Module } from '@nestjs/common';
import { FeedVersionService } from './feed-version.cache';
import { FeedInvalidationService } from './feed-invalidation.service';

/**
 * Feed invalidation, available everywhere.
 *
 * `@Global` for the same reason RealtimeModule is: the services that need to
 * invalidate a feed are the ones that write profiles, preferences and blocks —
 * they live in ProfilesModule, MatchesModule and BlocksModule, and none of
 * them should have to import a matching module to say "this member's feed
 * changed". Wiring it the other way round would also risk a cycle, since
 * MatchesModule already reaches into profile and block territory for its
 * feed queries.
 *
 * Deliberately narrow: only the two services with no dependencies of their own
 * beyond RedisService and the global RealtimeGateway. FeedContextService and
 * FeedSeenService stay in MatchesModule, because they depend on its
 * repositories and only the feed itself reads them.
 */
@Global()
@Module({
  providers: [FeedVersionService, FeedInvalidationService],
  exports: [FeedVersionService, FeedInvalidationService],
})
export class FeedCacheModule {}
