import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/profile_by_id_repository.dart';
import '../../data/repositories/discover_repository_impl.dart';
import '../../domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/discover_feed_entity.dart';
import '../../domain/repositories/discover_repository.dart';
import '../../../nearby/presentation/providers/nearby_providers.dart';

/// Real backend-backed repository — fetches `GET /discover` (the
/// preference-filtered feed) via the shared authenticated [ApiClient].
final profileByIdRepositoryProvider = Provider<ProfileByIdRepository>(
  (ref) => ProfileByIdRepository(ref.watch(apiClientProvider)),
);

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
        // Real proximity results from the device's location, not a slice of
        // the generic feed — the same notifier the Discover "Near You" section
        // and the Near Me screen read, so all three can never disagree about
        // who is nearby.
        //
        // Watched inside this branch on purpose: reaching it is what
        // subscribes. `discoverProfilesProvider` is also read by the Profile
        // screen, and an unconditional watch here would make opening THAT
        // screen create the nearby notifier. It would still take no location
        // reading (the notifier starts idle and does nothing until asked), but
        // the dependency would be a lie about what that screen needs.
        //
        // Empty until something resolves it. Nothing in the app currently
        // selects this filter — the only widget that set it was unused and
        // has been deleted — so this is the contract a future caller gets,
        // not a live code path. Whoever reintroduces such a control must also
        // render an idle/permission state, exactly as _NearYouSection does.
        final nearby = ref.watch(nearbyNotifierProvider);
        return nearby is NearbyLoaded ? nearby.profiles : const [];
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
