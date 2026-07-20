import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/storage_service.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../../domain/entities/search_filters_entity.dart';

/// Live (debounced by the search field itself) query text.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Criteria selected in the filter bottom sheet — stays populated until the
/// user explicitly resets it, independent of [searchQueryProvider].
final searchFiltersProvider = StateProvider<SearchFilters>(
  (ref) => const SearchFilters.empty(),
);

/// Locally-persisted recent search terms, most-recent first, capped at
/// [AppConstants.maxRecentSearches].
final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
  RecentSearchesNotifier.new,
);

class RecentSearchesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => storageService.recentSearches;

  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final deduped = state.where((e) => e.toLowerCase() != trimmed.toLowerCase());
    final updated = [trimmed, ...deduped].take(AppConstants.maxRecentSearches).toList();
    state = updated;
    await storageService.setRecentSearches(updated);
  }

  Future<void> removeOne(String query) async {
    final updated = state.where((e) => e != query).toList();
    state = updated;
    await storageService.setRecentSearches(updated);
  }

  Future<void> clearAll() async {
    state = const [];
    await storageService.setRecentSearches(const []);
  }
}

/// Every profile in the shared discover feed, deduped by id — the pool
/// Search queries against. No parallel repository or datasource; swapping
/// [discoverFeedProvider]'s backing repository for a real API later is the
/// only change a backend integration needs.
final _searchablePoolProvider =
    Provider<AsyncValue<List<DiscoveryProfileEntity>>>((ref) {
  final feedAsync = ref.watch(discoverFeedProvider);
  return feedAsync.whenData((feed) {
    final seenIds = <String>{};
    final pool = <DiscoveryProfileEntity>[];
    for (final profile in [
      ...feed.aiRecommended,
      ...feed.recentlyJoined,
      ...feed.verifiedProfiles,
      ...feed.nearYou,
      ...feed.premiumMembers,
    ]) {
      if (seenIds.add(profile.id)) pool.add(profile);
    }
    return pool;
  });
});

/// Re-projects the shared pool by [searchQueryProvider] (matched against
/// name, matrimony ID, city, profession and education) and
/// [searchFiltersProvider]. Recomputes only when query, filters, or the
/// underlying feed actually change.
final searchResultsProvider =
    Provider<AsyncValue<List<DiscoveryProfileEntity>>>((ref) {
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final filters = ref.watch(searchFiltersProvider);
  final poolAsync = ref.watch(_searchablePoolProvider);

  return poolAsync.whenData((pool) {
    return pool.where((profile) {
      if (!filters.matches(profile)) return false;
      if (query.isEmpty) return true;
      return profile.name.toLowerCase().contains(query) ||
          profile.matrimonyId.toLowerCase().contains(query) ||
          profile.location.toLowerCase().contains(query) ||
          profile.profession.toLowerCase().contains(query) ||
          profile.education.toLowerCase().contains(query);
    }).toList();
  });
});
