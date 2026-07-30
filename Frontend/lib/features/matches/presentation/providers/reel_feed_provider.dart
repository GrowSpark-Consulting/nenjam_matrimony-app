import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../discover/presentation/providers/discover_providers.dart';

/// Accumulating, paginated state for the Matches reel — the flat list of
/// profiles grown page-by-page as the user swipes down the vertical `PageView`.
class ReelFeedState {
  final List<DiscoveryProfileEntity> profiles;
  final int page;
  final bool hasMore;
  final bool isLoadingMore;

  const ReelFeedState({
    required this.profiles,
    required this.page,
    required this.hasMore,
    this.isLoadingMore = false,
  });

  ReelFeedState copyWith({
    List<DiscoveryProfileEntity>? profiles,
    int? page,
    bool? hasMore,
    bool? isLoadingMore,
  }) =>
      ReelFeedState(
        profiles: profiles ?? this.profiles,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );
}

/// Drives the infinite-scroll Matches reel. `build()` loads the first page;
/// [loadMore] appends the next one when the user nears the end. Dedupes by id
/// so a profile never appears twice, and never fires overlapping requests.
class ReelFeedNotifier extends AutoDisposeAsyncNotifier<ReelFeedState> {
  static const _pageSize = 20;

  @override
  Future<ReelFeedState> build() async {
    final page = await ref
        .watch(discoverRepositoryProvider)
        .getDiscoverProfilesPage(page: 1, limit: _pageSize);
    return ReelFeedState(
      profiles: page.items,
      page: page.page,
      hasMore: page.hasMore,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final next = await ref
          .read(discoverRepositoryProvider)
          .getDiscoverProfilesPage(page: current.page + 1, limit: _pageSize);
      final seen = current.profiles.map((p) => p.id).toSet();
      final merged = [
        ...current.profiles,
        ...next.items.where((p) => seen.add(p.id)),
      ];
      state = AsyncData(
        ReelFeedState(
          profiles: merged,
          page: next.page,
          hasMore: next.hasMore,
        ),
      );
    } catch (_) {
      // Keep the profiles already loaded; just clear the flag so a later swipe
      // can retry the next page.
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// Drops [profileId] from the loaded reel — e.g. right after the caller
  /// blocks that member. The `PageView` above this notifier tracks a numeric
  /// page index, not an item identity, so shrinking [profiles] is all that's
  /// needed for the next card to slide into place; no separate "advance to
  /// next" call exists or is required. No rollback on failure: by the time
  /// this is called the block request has already succeeded (see
  /// `SafetyRepository`'s doc comment — Discover/Search/Matches simply stop
  /// returning a blocked member once the request completes).
  void removeProfile(String profileId) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (!current.profiles.any((p) => p.id == profileId)) return;
    state = AsyncData(
      current.copyWith(
        profiles: current.profiles.where((p) => p.id != profileId).toList(),
      ),
    );
  }
}

final reelFeedProvider =
    AutoDisposeAsyncNotifierProvider<ReelFeedNotifier, ReelFeedState>(
  ReelFeedNotifier.new,
);
