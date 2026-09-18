import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/services/storage_service.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../data/repositories/search_repository_impl.dart';
import '../../domain/entities/search_filters_entity.dart';
import '../../domain/repositories/search_repository.dart';

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

/// Backend search, over the shared authenticated [ApiClient].
final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepositoryImpl(ref.watch(apiClientProvider)),
);

/// The term to ask the server for, or null when Search is idle (no query and
/// no filters — the screen shows suggestions and must not fire a request).
///
/// This exists so [SearchResultsNotifier] can depend on the *request* rather
/// than on the raw query and filters. It reads [searchFiltersProvider], so it
/// re-runs on every filter change — but its value only changes when the query
/// text or the idle/active state changes, and Riverpod compares values before
/// notifying. Adjusting a filter therefore re-projects the already-fetched
/// results instead of re-issuing an identical HTTP request (identical because
/// the endpoint takes no filter parameters — see [SearchRepository]).
final _searchRequestProvider = Provider<String?>((ref) {
  final query = ref.watch(searchQueryProvider).trim();
  final filters = ref.watch(searchFiltersProvider);
  if (query.isEmpty && filters.isEmpty) return null;
  return query;
});

/// Accumulating, paginated state for backend search. Mirrors
/// `ReelFeedState` — the pattern already used for the Matches reel.
class SearchResultsState {
  const SearchResultsState({
    required this.items,
    required this.page,
    required this.total,
    required this.hasMore,
    this.isLoadingMore = false,
  });

  const SearchResultsState.idle()
      : items = const [],
        page = 0,
        total = 0,
        hasMore = false,
        isLoadingMore = false;

  /// Raw server results, in server order, across every page loaded so far.
  /// Never filtered here — [filteredSearchResultsProvider] owns that.
  final List<DiscoveryProfileEntity> items;
  final int page;

  /// Server-reported total for the query, before client-side filters.
  final int total;
  final bool hasMore;
  final bool isLoadingMore;

  SearchResultsState copyWith({
    List<DiscoveryProfileEntity>? items,
    int? page,
    int? total,
    bool? hasMore,
    bool? isLoadingMore,
  }) =>
      SearchResultsState(
        items: items ?? this.items,
        page: page ?? this.page,
        total: total ?? this.total,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );
}

/// Drives server-side search with page-by-page loading.
///
/// `build()` fetches page 1 and re-runs automatically whenever
/// [_searchRequestProvider] changes — which is what resets pagination when the
/// query changes or Search goes idle. [loadMore] appends the next page;
/// [refresh] re-fetches from page 1.
class SearchResultsNotifier
    extends AutoDisposeAsyncNotifier<SearchResultsState> {
  static const _pageSize = 20;

  @override
  Future<SearchResultsState> build() async {
    final request = ref.watch(_searchRequestProvider);
    // Idle: no query and no filters. Return empty rather than asking the
    // server for the unfiltered feed behind the suggestions screen.
    if (request == null) return const SearchResultsState.idle();

    final page = await ref
        .watch(searchRepositoryProvider)
        .search(query: request, page: 1, limit: _pageSize);

    return SearchResultsState(
      items: page.items,
      page: page.page,
      total: page.total,
      hasMore: page.hasMore,
    );
  }

  /// Appends the next page. No-op while one is already in flight, so a scroll
  /// that crosses the trigger threshold repeatedly cannot stack requests.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    final request = ref.read(_searchRequestProvider);
    if (request == null) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final next = await ref.read(searchRepositoryProvider).search(
            query: request,
            page: current.page + 1,
            limit: _pageSize,
          );
      // Dedupe by id: a profile created between two page reads shifts the
      // window and can otherwise return the same row twice.
      final seen = current.items.map((p) => p.id).toSet();
      state = AsyncData(
        SearchResultsState(
          items: [
            ...current.items,
            ...next.items.where((p) => seen.add(p.id)),
          ],
          page: next.page,
          total: next.total,
          hasMore: next.hasMore,
        ),
      );
    } catch (_) {
      // A failed *next* page must not discard the results already on screen.
      // Clearing the flag alone lets a later scroll retry it — the same
      // recovery ReelFeedNotifier.loadMore uses.
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// Pull-to-refresh / retry: back to page 1 for the current request.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

/// Raw, unfiltered backend search state. Widgets that need pagination
/// (`loadMore`, `isLoadingMore`) read this; the grid reads
/// [filteredSearchResultsProvider].
final searchResultsProvider = AutoDisposeAsyncNotifierProvider<
    SearchResultsNotifier, SearchResultsState>(SearchResultsNotifier.new);

/// Backend results narrowed by [searchFiltersProvider].
///
/// Filtering is client-side because `GET /discover/search` accepts no filter
/// parameters (see [SearchRepository]). The backend result is still the source
/// of truth for *membership* — eligibility, blocks, suspended and incomplete
/// profiles are all decided server-side by `buildFeedWhere` and are never
/// re-checked here; this only narrows what the server already returned.
///
/// Note the consequence: filters apply to the pages loaded so far, not to the
/// whole result set, so a restrictive filter can show few matches until more
/// pages are loaded. Moving the filters server-side removes that entirely.
final filteredSearchResultsProvider =
    Provider.autoDispose<AsyncValue<List<DiscoveryProfileEntity>>>((ref) {
  final filters = ref.watch(searchFiltersProvider);
  final resultsAsync = ref.watch(searchResultsProvider);

  return resultsAsync.whenData((results) {
    if (filters.isEmpty) return results.items;
    return results.items.where(filters.matches).toList();
  });
});
