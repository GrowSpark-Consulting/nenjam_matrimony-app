import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/search/domain/entities/search_filters_entity.dart';
import 'package:nenjam_matrimony/features/search/domain/repositories/search_repository.dart';
import 'package:nenjam_matrimony/features/search/presentation/providers/search_providers.dart';

/// Records every call so a test can assert exactly what the provider asked
/// the server for — and, just as importantly, that it asked at all.
class _RecordingRepository implements SearchRepository {
  _RecordingRepository({this.pageBuilder, this.error});

  /// Builds the page returned for a given (query, page). Defaults to two
  /// profiles per page with `hasMore` true, so pagination is exercisable.
  SearchResultPage Function(String query, int page)? pageBuilder;

  /// Thrown instead of returning, when set.
  Object? error;

  final List<({String query, int page, int limit})> calls = [];

  @override
  Future<SearchResultPage> search({
    required String query,
    int page = 1,
    int limit = 20,
  }) async {
    calls.add((query: query, page: page, limit: limit));
    if (error != null) throw error!;
    final build = pageBuilder ?? _defaultPage;
    return build(query, page);
  }

  static SearchResultPage _defaultPage(String query, int page) {
    final start = (page - 1) * 2;
    return SearchResultPage(
      items: [
        _profile('p${start + 1}'),
        _profile('p${start + 2}'),
      ],
      page: page,
      limit: 20,
      total: 6,
      hasMore: page < 3,
    );
  }
}

DiscoveryProfileEntity _profile(
  String id, {
  int age = 28,
  String religion = 'Hindu',
}) =>
    DiscoveryProfileEntity(
      id: id,
      matrimonyId: id.toUpperCase(),
      name: 'Member $id',
      age: age,
      location: 'Chennai, Tamil Nadu',
      profession: 'Engineer',
      education: 'B.E.',
      photoUrls: const ['https://example.test/photo.jpg'],
      religion: religion,
    );

ProviderContainer _container(_RecordingRepository repo) {
  final container = ProviderContainer(
    overrides: [searchRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  // searchResultsProvider is autoDispose — without a listener it would be
  // torn down between reads and refetch every time.
  container.listen(searchResultsProvider, (_, __) {});
  return container;
}

/// Lets the notifier's pending future complete.
Future<void> _settle(ProviderContainer container) =>
    container.read(searchResultsProvider.future);

void main() {
  group('searchResultsProvider — backend wiring', () {
    test('idle (no query, no filters) issues no request', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);

      await _settle(container);

      expect(repo.calls, isEmpty);
      expect(container.read(searchResultsProvider).value!.items, isEmpty);
    });

    test('setting a query issues exactly one GET for page 1', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      await _settle(container);

      container.read(searchQueryProvider.notifier).state = 'chennai';
      await _settle(container);

      expect(repo.calls, hasLength(1));
      expect(repo.calls.single.query, 'chennai');
      expect(repo.calls.single.page, 1);
      expect(repo.calls.single.limit, 20);
    });

    test('results come from the repository, not from any feed', () async {
      final repo = _RecordingRepository(
        pageBuilder: (_, __) => SearchResultPage(
          items: [_profile('from-server')],
          page: 1,
          limit: 20,
          total: 1,
          hasMore: false,
        ),
      );
      final container = _container(repo);
      container.read(searchQueryProvider.notifier).state = 'x';
      await _settle(container);

      final results = container.read(filteredSearchResultsProvider).value!;
      expect(results.single.id, 'from-server');
    });

    test('changing the query resets pagination to page 1', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);

      container.read(searchQueryProvider.notifier).state = 'first';
      await _settle(container);
      await container.read(searchResultsProvider.notifier).loadMore();
      expect(container.read(searchResultsProvider).value!.page, 2);

      container.read(searchQueryProvider.notifier).state = 'second';
      await _settle(container);

      expect(repo.calls.last.query, 'second');
      expect(repo.calls.last.page, 1);
      expect(container.read(searchResultsProvider).value!.page, 1);
      expect(container.read(searchResultsProvider).value!.items, hasLength(2));
    });

    test('clearing the query back to idle stops requesting', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);

      container.read(searchQueryProvider.notifier).state = 'x';
      await _settle(container);
      final afterQuery = repo.calls.length;

      container.read(searchQueryProvider.notifier).state = '';
      await _settle(container);

      expect(repo.calls, hasLength(afterQuery));
      expect(container.read(searchResultsProvider).value!.items, isEmpty);
    });
  });

  group('pagination', () {
    test('loadMore appends the next page', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      container.read(searchQueryProvider.notifier).state = 'x';
      await _settle(container);

      expect(container.read(searchResultsProvider).value!.items, hasLength(2));

      await container.read(searchResultsProvider.notifier).loadMore();

      final state = container.read(searchResultsProvider).value!;
      expect(state.items, hasLength(4));
      expect(state.page, 2);
      expect(state.hasMore, isTrue);
      expect(repo.calls.map((c) => c.page), [1, 2]);
    });

    test('loadMore stops at the last page', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      container.read(searchQueryProvider.notifier).state = 'x';
      await _settle(container);

      final notifier = container.read(searchResultsProvider.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      expect(container.read(searchResultsProvider).value!.hasMore, isFalse);

      final callsAtEnd = repo.calls.length;
      await notifier.loadMore();

      expect(repo.calls, hasLength(callsAtEnd),
          reason: 'no request once hasMore is false');
    });

    test('overlapping loadMore calls do not stack requests', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      container.read(searchQueryProvider.notifier).state = 'x';
      await _settle(container);

      final notifier = container.read(searchResultsProvider.notifier);
      await Future.wait([
        notifier.loadMore(),
        notifier.loadMore(),
        notifier.loadMore(),
      ]);

      expect(repo.calls.map((c) => c.page), [1, 2],
          reason: 'the second and third calls are dropped while one is '
              'already in flight');
    });

    test('duplicate ids across pages are not appended twice', () async {
      final repo = _RecordingRepository(
        pageBuilder: (_, page) => SearchResultPage(
          // Page 2 repeats p1 — what a row inserted between reads causes.
          items: page == 1
              ? [_profile('p1'), _profile('p2')]
              : [_profile('p2'), _profile('p3')],
          page: page,
          limit: 20,
          total: 3,
          hasMore: page < 2,
        ),
      );
      final container = _container(repo);
      container.read(searchQueryProvider.notifier).state = 'x';
      await _settle(container);

      await container.read(searchResultsProvider.notifier).loadMore();

      final ids =
          container.read(searchResultsProvider).value!.items.map((p) => p.id);
      expect(ids, ['p1', 'p2', 'p3']);
    });

    test('a failed next page keeps the results already on screen', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      container.read(searchQueryProvider.notifier).state = 'x';
      await _settle(container);

      repo.error = ApiException(500, 'boom');
      await container.read(searchResultsProvider.notifier).loadMore();

      final state = container.read(searchResultsProvider).value!;
      expect(state.items, hasLength(2), reason: 'page 1 survives');
      expect(state.isLoadingMore, isFalse, reason: 'a retry is possible');
      expect(container.read(searchResultsProvider).hasError, isFalse);
    });

    test('refresh re-fetches from page 1', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      container.read(searchQueryProvider.notifier).state = 'x';
      await _settle(container);
      await container.read(searchResultsProvider.notifier).loadMore();

      await container.read(searchResultsProvider.notifier).refresh();

      expect(repo.calls.last.page, 1);
      expect(container.read(searchResultsProvider).value!.items, hasLength(2));
      expect(container.read(searchResultsProvider).value!.page, 1);
    });
  });

  group('filters', () {
    test('activating a filter narrows the backend results', () async {
      final repo = _RecordingRepository(
        pageBuilder: (_, __) => SearchResultPage(
          items: [
            _profile('hindu', religion: 'Hindu'),
            _profile('christian', religion: 'Christian'),
          ],
          page: 1,
          limit: 20,
          total: 2,
          hasMore: false,
        ),
      );
      final container = _container(repo);
      container.read(searchQueryProvider.notifier).state = 'x';
      await _settle(container);

      expect(container.read(filteredSearchResultsProvider).value, hasLength(2));

      container.read(searchFiltersProvider.notifier).state =
          const SearchFilters(religion: 'Hindu');
      await _settle(container);

      final filtered = container.read(filteredSearchResultsProvider).value!;
      expect(filtered.single.id, 'hindu');
    });

    test('a filter alone (no query) triggers a backend search with a blank '
        'term', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      await _settle(container);
      expect(repo.calls, isEmpty);

      container.read(searchFiltersProvider.notifier).state =
          const SearchFilters(religion: 'Hindu');
      await _settle(container);

      expect(repo.calls, hasLength(1));
      expect(repo.calls.single.query, '');
      expect(repo.calls.single.page, 1);
    });

    test('changing a filter does not re-issue an identical request', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      container.read(searchQueryProvider.notifier).state = 'doctor';
      await _settle(container);
      expect(repo.calls, hasLength(1));

      // The endpoint takes no filter parameters, so refetching here would
      // send the byte-identical request and discard loaded pages.
      container.read(searchFiltersProvider.notifier).state =
          const SearchFilters(religion: 'Hindu');
      await _settle(container);
      container.read(searchFiltersProvider.notifier).state =
          const SearchFilters(ageRange: RangeValues(25, 35));
      await _settle(container);

      expect(repo.calls, hasLength(1));
    });

    test('resetting filters restores the full backend result set', () async {
      final repo = _RecordingRepository(
        pageBuilder: (_, __) => SearchResultPage(
          items: [
            _profile('a', religion: 'Hindu'),
            _profile('b', religion: 'Christian'),
          ],
          page: 1,
          limit: 20,
          total: 2,
          hasMore: false,
        ),
      );
      final container = _container(repo);
      container.read(searchQueryProvider.notifier).state = 'x';
      await _settle(container);

      container.read(searchFiltersProvider.notifier).state =
          const SearchFilters(religion: 'Hindu');
      await _settle(container);
      expect(container.read(filteredSearchResultsProvider).value, hasLength(1));

      container.read(searchFiltersProvider.notifier).state =
          const SearchFilters.empty();
      await _settle(container);

      expect(container.read(filteredSearchResultsProvider).value, hasLength(2));
    });
  });

  group('error handling', () {
    test('a failed first page surfaces as AsyncError', () async {
      final repo = _RecordingRepository(error: ApiException(401, 'no token'));
      final container = _container(repo);

      container.read(searchQueryProvider.notifier).state = 'x';
      await expectLater(
        container.read(searchResultsProvider.future),
        throwsA(isA<ApiException>()),
      );

      expect(container.read(searchResultsProvider).hasError, isTrue);
      expect(container.read(filteredSearchResultsProvider).hasError, isTrue);
    });

    test('refresh recovers after the failure clears', () async {
      final repo = _RecordingRepository(error: ApiException(500, 'boom'));
      final container = _container(repo);
      container.read(searchQueryProvider.notifier).state = 'x';
      await expectLater(
        container.read(searchResultsProvider.future),
        throwsA(isA<ApiException>()),
      );

      repo.error = null;
      await container.read(searchResultsProvider.notifier).refresh();

      expect(container.read(searchResultsProvider).hasError, isFalse);
      expect(container.read(searchResultsProvider).value!.items, hasLength(2));
    });
  });
}
