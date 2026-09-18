import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/search/domain/entities/search_filters_entity.dart';
import 'package:nenjam_matrimony/features/search/domain/repositories/search_repository.dart';
import 'package:nenjam_matrimony/features/search/presentation/pages/search_page.dart';
import 'package:nenjam_matrimony/features/search/presentation/providers/search_providers.dart';
import 'package:nenjam_matrimony/features/search/presentation/widgets/search_suggestions.dart';
import 'package:nenjam_matrimony/features/shortlist/domain/repositories/shortlist_repository.dart';
import 'package:nenjam_matrimony/features/shortlist/presentation/providers/shortlist_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Widget-level coverage for [SearchPage]: the states a user actually sees,
/// driven entirely through provider overrides — no network, no Firebase.
///
/// Per flutter-testing's "test important widget states and user
/// interactions": loading, empty, error+retry and results are each exercised
/// here; request-shape and pagination logic are covered separately in
/// search_repository_test.dart / search_providers_test.dart, so this file
/// does not repeat them.
void main() {
  // SearchSuggestions reads the storageService singleton (recent searches)
  // directly, the same as the rest of the app — not through a provider, so
  // it needs real init rather than a Riverpod override.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });

  group('SearchPage', () {
    testWidgets('idle: shows suggestions, not the results grid', (
      tester,
    ) async {
      await _pump(tester, repository: _FakeSearchRepository());

      expect(find.byType(SearchSuggestions), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
    });

    testWidgets('typing a query shows a loading state then results', (
      tester,
    ) async {
      final repository = _FakeSearchRepository(
        page: (_, __) async => SearchResultPage(
          items: [_profile('a', name: 'Asha')],
          page: 1,
          limit: 20,
          total: 1,
          hasMore: false,
        ),
      );

      await _pump(tester, repository: repository);
      await tester.enterText(find.byType(TextField), 'asha');
      await tester.pump(const Duration(milliseconds: 400)); // clears debounce

      // The request is in flight — shimmer, not the grid, and not the old
      // suggestions screen.
      await tester.pump();
      expect(find.byType(SearchSuggestions), findsNothing);

      await tester.pumpAndSettle();

      // ProfileCard renders '$name, $age' as one Text widget.
      expect(find.text('Asha, 28'), findsOneWidget);
      expect(repository.calls, [('asha', 1)]);
    });

    testWidgets('submitting an empty result set shows the empty state', (
      tester,
    ) async {
      final repository = _FakeSearchRepository(
        page: (_, __) async => const SearchResultPage(
          items: [],
          page: 1,
          limit: 20,
          total: 0,
          hasMore: false,
        ),
      );

      await _pump(tester, repository: repository);
      await tester.enterText(find.byType(TextField), 'zzzz-no-match');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
    });

    testWidgets('an API failure shows the error state with a working retry', (
      tester,
    ) async {
      var shouldFail = true;
      final repository = _FakeSearchRepository(
        page: (query, page) async {
          if (shouldFail) throw Exception('network down');
          return SearchResultPage(
            items: [_profile('a', name: 'Recovered')],
            page: 1,
            limit: 20,
            total: 1,
            hasMore: false,
          );
        },
      );

      await _pump(tester, repository: repository);
      await tester.enterText(find.byType(TextField), 'query');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // Error surfaced, not a crash and not an empty-results screen.
      expect(find.text('Something went wrong'), findsOneWidget);

      shouldFail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Recovered, 28'), findsOneWidget);
    });

    testWidgets(
        'a filter-only search with no matches can be reset back to idle',
        (tester) async {
      final repository = _FakeSearchRepository(
        page: (_, __) async => const SearchResultPage(
          items: [],
          page: 1,
          limit: 20,
          total: 0,
          hasMore: false,
        ),
      );

      await _pump(tester, repository: repository);
      // No text query — a filter alone is enough to leave idle (see
      // search_providers_test.dart's equivalent request-shape coverage).
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchPage)),
      );
      container.read(searchFiltersProvider.notifier).state =
          const SearchFilters(religion: 'Zoroastrian');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);

      await tester.tap(find.text('Reset Filters'));
      await tester.pumpAndSettle();

      // Query was never set, so clearing filters returns to idle —
      // suggestions, not another empty/error state.
      expect(find.byType(SearchSuggestions), findsOneWidget);
    });
  });
}

DiscoveryProfileEntity _profile(String id, {required String name}) =>
    DiscoveryProfileEntity(
      id: id,
      matrimonyId: id.toUpperCase(),
      name: name,
      age: 28,
      location: 'Chennai, Tamil Nadu',
      profession: 'Engineer',
      education: 'B.E.',
      photoUrls: const [],
    );

/// Records (query, page) for every call and delegates to [page] for the
/// response — defaults to one empty page so a test that doesn't care about
/// the payload still gets a well-formed result.
class _FakeSearchRepository implements SearchRepository {
  _FakeSearchRepository({this.page});

  Future<SearchResultPage> Function(String query, int page)? page;
  final List<(String, int)> calls = [];

  @override
  Future<SearchResultPage> search({
    required String query,
    int page = 1,
    int limit = 20,
  }) async {
    calls.add((query, page));
    if (this.page != null) return this.page!(query, page);
    return SearchResultPage(items: const [], page: page, limit: limit, total: 0, hasMore: false);
  }
}

/// No shortlisted profiles, and no network — the card grid's shortlist icon
/// reads this via `isShortlistedProvider`.
class _FakeShortlistRepository implements ShortlistRepository {
  @override
  Future<List<DiscoveryProfileEntity>> getShortlisted({int page = 1, int limit = 20}) async => const [];

  @override
  Future<void> add(DiscoveryProfileEntity profile) async {}

  @override
  Future<void> remove(String profileId) async {}
}

Future<void> _pump(
  WidgetTester tester, {
  required SearchRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchRepositoryProvider.overrideWithValue(repository),
        shortlistRepositoryProvider.overrideWithValue(_FakeShortlistRepository()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SearchPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
