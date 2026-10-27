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

/// Profiles AI Recommended has paged in past [discoverFeedProvider]'s first
/// page, and whether it can page further.
class DiscoverMoreState {
  final List<DiscoveryProfileEntity> profiles;
  final String? cursor;
  final bool hasMore;
  final bool isLoadingMore;

  /// The last [DiscoverMoreNotifier.loadMore] failed. Cleared by the next try.
  final bool loadFailed;

  const DiscoverMoreState({
    this.profiles = const [],
    this.cursor,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadFailed = false,
  });
}

/// Continues AI Recommended from the cursor the sectioned feed's own page
/// handed back, so a member can keep going past the first 50 profiles.
///
/// Rebuilds — dropping everything it appended — whenever [discoverFeedProvider]
/// does (pull-to-refresh, a realtime `feed.invalidate`), so a refreshed feed
/// never carries pages that belong to an older ranking. Skips any profile the
/// screen already shows, in any section, and never overlaps two requests.
class DiscoverMoreNotifier extends Notifier<DiscoverMoreState> {
  static const _pageSize = 20;

  /// The feed page [build] last ran for. [loadMore] dedupes against it.
  DiscoverFeedEntity? _feed;

  /// Bumped by every [build]. A page that comes back under a different
  /// generation was requested for a feed that has since been refreshed, and
  /// is dropped. Checked without `ref`: after a refresh Riverpod forbids `ref`
  /// calls until this provider rebuilds, and the response can land first.
  int _generation = 0;

  @override
  DiscoverMoreState build() {
    _generation++;
    final feedAsync = ref.watch(discoverFeedProvider);
    // Nothing to page while a refresh is in flight: the previous feed's
    // cursor would fetch a page that the new feed is about to replace.
    final feed = feedAsync.isLoading ? null : feedAsync.valueOrNull;
    _feed = feed;
    final cursor = feed?.nextCursor;
    return DiscoverMoreState(
      cursor: cursor,
      hasMore: (feed?.hasMore ?? false) && cursor != null,
    );
  }

  Future<void> loadMore() async {
    final current = state;
    final cursor = current.cursor;
    final feed = _feed;
    if (!current.hasMore || current.isLoadingMore || cursor == null) return;
    if (feed == null) return;
    final generation = _generation;
    final repository = ref.read(discoverRepositoryProvider);

    state = DiscoverMoreState(
      profiles: current.profiles,
      cursor: cursor,
      hasMore: true,
      isLoadingMore: true,
    );
    try {
      final page = await repository.getDiscoverProfilesPage(
        limit: _pageSize,
        cursor: cursor,
      );
      if (generation != _generation) return;
      final seen = {...feed.profileIds, for (final p in current.profiles) p.id};
      state = DiscoverMoreState(
        profiles: [
          ...current.profiles,
          ...page.items.where((p) => seen.add(p.id)),
        ],
        cursor: page.nextCursor,
        hasMore: page.hasMore && page.nextCursor != null,
      );
    } catch (_) {
      if (generation != _generation) return;
      state = DiscoverMoreState(
        profiles: current.profiles,
        cursor: cursor,
        hasMore: true,
        loadFailed: true,
      );
    }
  }
}

final discoverMoreProfilesProvider =
    NotifierProvider<DiscoverMoreNotifier, DiscoverMoreState>(
      DiscoverMoreNotifier.new,
    );

/// Which of the three Discover tabs is active.
enum DiscoverFilter { forYou, nearMe, newProfiles }

final discoverFilterProvider = StateProvider<DiscoverFilter>(
  (ref) => DiscoverFilter.forYou,
);

/// Re-projects the discover feed into one continuous swipeable stream per
/// filter tab — no parallel repository, datasource, or duplicate model.
final discoverProfilesProvider = Provider<AsyncValue<List<DiscoveryProfileEntity>>>((
  ref,
) {
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
