import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../home/domain/entities/discovery_profile_entity.dart';
import '../../../home/presentation/providers/home_providers.dart';

/// Which of the three Discover tabs is active.
enum DiscoverFilter { forYou, nearMe, newProfiles }

final discoverFilterProvider = StateProvider<DiscoverFilter>(
  (ref) => DiscoverFilter.forYou,
);

/// Discover re-projects the exact same [DiscoveryProfileEntity] feed Home is
/// built on into one continuous swipeable stream — no parallel repository,
/// datasource, or duplicate model. Swapping [HomeRepositoryImpl] still
/// updates both screens at once.
final discoverProfilesProvider = Provider<AsyncValue<List<DiscoveryProfileEntity>>>((ref) {
  final filter = ref.watch(discoverFilterProvider);
  final feedAsync = ref.watch(homeFeedProvider);

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
