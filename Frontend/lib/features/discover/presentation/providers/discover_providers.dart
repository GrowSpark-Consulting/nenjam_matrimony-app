import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/discover_repository_impl.dart';
import '../../domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/discover_feed_entity.dart';
import '../../domain/repositories/discover_repository.dart';

/// Real backend-backed repository — fetches `GET /discover` (the
/// preference-filtered feed) via the shared authenticated [ApiClient].
final discoverRepositoryProvider = Provider<DiscoverRepository>(
  (ref) => DiscoverRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Drives the Discover feed screen — and, by reprojection, the Matches reels,
/// Search pool, and "similar profiles" shelf. All real backend data.
final discoverFeedProvider = FutureProvider<DiscoverFeedEntity>(
  (ref) => ref.watch(discoverRepositoryProvider).getDiscoverFeed(),
);

/// Which of the three Discover tabs is active.
enum DiscoverFilter { forYou, nearMe, newProfiles }

final discoverFilterProvider = StateProvider<DiscoverFilter>(
  (ref) => DiscoverFilter.forYou,
);

/// Re-projects the discover feed into one continuous swipeable stream per
/// filter tab — no parallel repository, datasource, or duplicate model.
final discoverProfilesProvider = Provider<AsyncValue<List<DiscoveryProfileEntity>>>((ref) {
  final filter = ref.watch(discoverFilterProvider);
  final feedAsync = ref.watch(discoverFeedProvider);

  return feedAsync.whenData((feed) {
    switch (filter) {
      case DiscoverFilter.nearMe:
        return feed.nearYou;
      case DiscoverFilter.newProfiles:
        return feed.recentlyJoined;
      case DiscoverFilter.forYou:
        return [
          ...feed.aiRecommended,
          ...feed.verifiedProfiles,
          ...feed.premiumMembers,
        ];
    }
  });
});
