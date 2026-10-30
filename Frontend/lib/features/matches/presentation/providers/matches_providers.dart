import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../discover/presentation/providers/discover_providers.dart';

/// The Matches feed categories, left to right after the leading Search
/// action. Search itself is a pure navigation shortcut to the Search
/// screen — not a feed filter — so it has no entry here.
enum MatchCategory { newProfiles, daily, myMatches, nearMe, moreMatches }

/// Currently selected Matches category.
final matchCategoryProvider = StateProvider<MatchCategory>(
  (ref) => MatchCategory.newProfiles,
);

/// Re-projects the shared discover feed into one swipeable stream per
/// Matches category — no parallel repository, datasource, or duplicate
/// model. Swapping in a dedicated backend endpoint per category later only
/// requires changing the branch bodies below.
final matchCategoryFeedProvider =
    Provider<AsyncValue<List<DiscoveryProfileEntity>>>((ref) {
      final category = ref.watch(matchCategoryProvider);
      final feedAsync = ref.watch(discoverFeedProvider);

      return feedAsync.whenData((feed) {
        switch (category) {
          case MatchCategory.newProfiles:
            return feed.recentlyJoined;
          case MatchCategory.daily:
            // TODO(backend): no dedicated daily-recommendations endpoint exists
            // yet — temporarily reuse the shared discover feed so the reel never
            // shows an empty state; swap this branch for a real call once one
            // exists.
            return [
              ...feed.aiRecommended,
              ...feed.verifiedProfiles,
              ...feed.premiumMembers,
            ];
          case MatchCategory.myMatches:
            return feed.aiRecommended;
          case MatchCategory.nearMe:
            // Unreachable in practice: the Near Me chip opens the dedicated
            // location-based screen (features/nearby) instead of selecting this
            // category, so this state is never entered from the UI. Kept as a
            // defensive default rather than deleted, because removing the enum
            // value would ripple through the chip bar, its GlobalKey map and the
            // notification deep-link service for no behavioural gain.
            return feed.nearYou;
          case MatchCategory.moreMatches:
            return [...feed.verifiedProfiles, ...feed.premiumMembers];
        }
      });
    });
