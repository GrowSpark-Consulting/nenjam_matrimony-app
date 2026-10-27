import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/location/device_location_service.dart';
import 'package:nenjam_matrimony/core/services/location/location_providers.dart';
import 'package:nenjam_matrimony/core/widgets/buttons/primary_button.dart';
import 'package:nenjam_matrimony/core/widgets/feedback/shimmer_widget.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/presentation/pages/discover_page.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/inbox/domain/entities/conversation_entity.dart';
import 'package:nenjam_matrimony/features/inbox/domain/repositories/conversation_repository.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/widgets/empty_inbox.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/widgets/inbox_preview_panel.dart';
import 'package:nenjam_matrimony/features/nearby/domain/repositories/nearby_repository.dart';
import 'package:nenjam_matrimony/features/nearby/presentation/providers/nearby_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import '../../support/responsive_harness.dart';

/// Discover's Near You grid derives its column count from the width the
/// section actually has (via AdaptiveGrid), not from `isDesktop`.
///
/// Discover itself is a sectioned editorial page, not a profile feed, so the
/// only grid on it is Near You and the only thing asserted about layout here
/// is that grid and its shimmer placeholder.
///
/// The expected column counts below are written out as literals on purpose.
/// Recomputing them with AdaptiveGrid would make the test agree with the
/// implementation by construction.
void main() {
  group('Near You columns follow the available width', () {
    // 136px is the narrowest tile the two-up phone layout already used, so:
    // 2 columns up to 471, 3 from 472, 4 from 624. Four is the cap.
    final expectedColumns = <double, int>{
      320: 2,
      360: 2,
      375: 2,
      390: 2,
      430: 2,
      471: 2,
      472: 3,
      599: 3,
      600: 3,
      623: 3,
      624: 4,
      768: 4,
      899: 4,
      900: 4,
      1023: 4,
      1024: 4,
      1199: 4,
      1200: 4,
      1440: 4,
      1920: 4,
      3440: 4,
    };

    for (final entry in expectedColumns.entries) {
      final width = entry.key;
      final columns = entry.value;
      testWidgets('${width.toInt()}px lays out $columns columns', (
        tester,
      ) async {
        final errors = await _pumpDiscover(
          tester,
          Size(width, 900),
          nearby: _FakeNearbyRepository(_profiles(4)),
        );
        expectNoOverflowIn(errors);

        expect(_columnsOf(tester), columns);
      });
    }

    testWidgets('window class tiers: compact, medium, expanded, large', (
      tester,
    ) async {
      // One representative width per WindowClass, so a regression reads as a
      // tier rather than a magic number.
      final seen = <String, int>{};
      for (final tier in {
        'compact': 360.0,
        'medium': 700.0,
        'expanded': 1000.0,
        'large': 1440.0,
      }.entries) {
        final errors = await _pumpDiscover(
          tester,
          Size(tier.value, 900),
          nearby: _FakeNearbyRepository(_profiles(4)),
        );
        expectNoOverflowIn(errors);
        seen[tier.key] = _columnsOf(tester);
      }
      expect(seen, {'compact': 2, 'medium': 4, 'expanded': 4, 'large': 4});
    });
  });

  group('Near You cards', () {
    testWidgets('two cards share a row on a phone, four on a desktop', (
      tester,
    ) async {
      var errors = await _pumpDiscover(
        tester,
        const Size(360, 800),
        nearby: _FakeNearbyRepository(_profiles(4)),
      );
      expectNoOverflowIn(errors);
      expect(_rowsOfCards(tester, 4), [2, 2]);

      errors = await _pumpDiscover(
        tester,
        const Size(1440, 900),
        nearby: _FakeNearbyRepository(_profiles(4)),
      );
      expectNoOverflowIn(errors);
      expect(_rowsOfCards(tester, 4), [4]);
    });

    testWidgets('the four-card teaser cap survives at every width', (
      tester,
    ) async {
      for (final width in [360.0, 1440.0, 3440.0]) {
        final errors = await _pumpDiscover(
          tester,
          Size(width, 900),
          nearby: _FakeNearbyRepository(_profiles(7)),
        );
        expectNoOverflowIn(errors);
        expect(
          _cardNames(7).where(
            (n) => find.text(n, skipOffstage: false).evaluate().isNotEmpty,
          ),
          _cardNames(4),
          reason: 'only the first four of seven profiles render at $width',
        );
      }
    });

    testWidgets('card shape is the same 0.75 ratio at every width', (
      tester,
    ) async {
      for (final width in [360.0, 1440.0]) {
        final errors = await _pumpDiscover(
          tester,
          Size(width, 900),
          nearby: _FakeNearbyRepository(_profiles(4)),
        );
        expectNoOverflowIn(errors);
        expect(_delegateOf(tester).childAspectRatio, 0.75);
      }
    });
  });

  group('Near You loading placeholder', () {
    // A fetch that never completes holds the section in NearbyLoading.
    for (final width in [320.0, 360.0, 472.0, 600.0, 900.0, 1440.0]) {
      testWidgets('${width.toInt()}px: one row of shimmer, no profile data', (
        tester,
      ) async {
        final repository = _FakeNearbyRepository(
          _profiles(4),
          gate: Completer<void>(),
        );
        final errors = await _pumpDiscover(
          tester,
          Size(width, 900),
          nearby: repository,
        );
        expectNoOverflowIn(errors);

        final columns = _columnsOf(tester);
        final grid = tester.widget<GridView>(_gridFinder);
        final delegate = grid.childrenDelegate as SliverChildBuilderDelegate;

        // The placeholder count IS the column count: exactly one row.
        expect(delegate.estimatedChildCount, columns);
        expect(
          find.byType(NmShimmer, skipOffstage: false),
          findsNWidgets(columns),
        );
        expect(_delegateOf(tester).childAspectRatio, 0.75);

        // Placeholders never pass through the profile card path.
        for (final name in _cardNames(4)) {
          expect(find.text(name, skipOffstage: false), findsNothing);
        }
      });
    }

    testWidgets('placeholder and real grid agree on column count', (
      tester,
    ) async {
      final gate = Completer<void>();
      final repository = _FakeNearbyRepository(_profiles(4), gate: gate);
      await _pumpDiscover(tester, const Size(1440, 900), nearby: repository);
      final loadingColumns = _columnsOf(tester);

      gate.complete();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(NmShimmer, skipOffstage: false), findsNothing);
      expect(
        find.text(_cardNames(4).first, skipOffstage: false),
        findsOneWidget,
      );
      expect(_columnsOf(tester), loadingColumns);
    });
  });

  group('Near You non-result states', () {
    for (final width in [320.0, 600.0, 1440.0]) {
      testWidgets('${width.toInt()}px: fetch failure shows retry', (
        tester,
      ) async {
        final errors = await _pumpDiscover(
          tester,
          Size(width, 900),
          nearby: _FakeNearbyRepository(const [], throwOnFetch: true),
        );
        expectNoOverflowIn(errors);
        expect(find.text('Try Again', skipOffstage: false), findsOneWidget);
        expect(_gridFinder, findsNothing);
      });

      testWidgets('${width.toInt()}px: nobody nearby hides the section', (
        tester,
      ) async {
        final errors = await _pumpDiscover(
          tester,
          Size(width, 900),
          nearby: _FakeNearbyRepository(const []),
        );
        expectNoOverflowIn(errors);
        expect(find.text('Near You', skipOffstage: false), findsNothing);
        expect(_gridFinder, findsNothing);
      });

      testWidgets('${width.toInt()}px: permission needed shows the prompt', (
        tester,
      ) async {
        final errors = await _pumpDiscover(
          tester,
          Size(width, 900),
          nearby: _FakeNearbyRepository(const []),
          location: _FakeLocationService(const LocationPermissionDenied()),
        );
        expectNoOverflowIn(errors);
        expect(
          find.text('Enable Location', skipOffstage: false),
          findsOneWidget,
        );
        expect(_gridFinder, findsNothing);
      });
    }
  });

  group('narrow surfaces', () {
    testWidgets('320x568 renders loaded Near You without overflow', (
      tester,
    ) async {
      final errors = await _pumpDiscover(
        tester,
        const Size(320, 568),
        nearby: _FakeNearbyRepository(_profiles(4)),
      );
      expectNoOverflowIn(errors);
      expect(_columnsOf(tester), 2);
    });

    testWidgets('continuous resize through every boundary stays valid', (
      tester,
    ) async {
      final errors = await _pumpDiscover(
        tester,
        const Size(360, 900),
        nearby: _FakeNearbyRepository(_profiles(4)),
      );
      expectNoOverflowIn(errors);
      expect(_columnsOf(tester), 2);

      // 599 -> 3, 600 -> 3, 899/900/1023/1024/1199/1200 -> 4.
      const expectedAfterResize = {
        599: 3,
        600: 3,
        899: 4,
        900: 4,
        1023: 4,
        1024: 4,
        1199: 4,
        1200: 4,
      };
      for (final width in kBoundaryWidths) {
        final stepErrors = await resizeTo(tester, Size(width, 900));
        expectNoOverflowIn(stepErrors);
        expect(
          _columnsOf(tester),
          expectedAfterResize[width.toInt()],
          reason: 'columns at ${width}px after a live resize',
        );
      }

      final backErrors = await resizeTo(tester, const Size(360, 900));
      expectNoOverflowIn(backErrors);
      expect(_columnsOf(tester), 2);
    });
  });

  group('Inbox panel on wide Discover', () {
    for (final width in [360.0, 768.0, 1024.0, 1199.0]) {
      testWidgets('${width.toInt()}px: no panel', (tester) async {
        final errors = await _pumpDiscover(
          tester,
          Size(width, 900),
          nearby: _FakeNearbyRepository(_profiles(4)),
        );
        expectNoOverflowIn(errors);
        expect(_panelFinder, findsNothing);
      });
    }

    for (final width in [1200.0, 1440.0, 1920.0, 3440.0]) {
      testWidgets('${width.toInt()}px: one 320px panel', (tester) async {
        final errors = await _pumpDiscover(
          tester,
          Size(width, 900),
          nearby: _FakeNearbyRepository(_profiles(4)),
        );
        expectNoOverflowIn(errors);
        expect(_panelFinder, findsOneWidget);
        expect(tester.getSize(_panelFinder).width, 320);
        // The panel sits on the right edge of the page.
        expect(tester.getTopRight(_panelFinder).dx, width);
      });
    }

    testWidgets('a live resize across 1200px adds and removes it', (
      tester,
    ) async {
      final errors = await _pumpDiscover(
        tester,
        const Size(1199, 900),
        nearby: _FakeNearbyRepository(_profiles(4)),
      );
      expectNoOverflowIn(errors);
      expect(_panelFinder, findsNothing);

      expectNoOverflowIn(await resizeTo(tester, const Size(1200, 900)));
      expect(_panelFinder, findsOneWidget);

      expectNoOverflowIn(await resizeTo(tester, const Size(1199, 900)));
      expect(_panelFinder, findsNothing);
    });

    testWidgets('beside the panel, the feed is centered at the feed width', (
      tester,
    ) async {
      final errors = await _pumpDiscover(
        tester,
        const Size(1920, 900),
        nearby: _FakeNearbyRepository(_profiles(4)),
      );
      expectNoOverflowIn(errors);
      // Feed column: 1920 - 320 panel = 1600. Feed content: 680, centered, so
      // a 460px gutter each side. Near You pads itself 16px inside that.
      expect(tester.getSize(_gridFinder).width, 648);
      expect(tester.getTopLeft(_gridFinder).dx, 476);
      expect(_columnsOf(tester), 4);
    });

    testWidgets('without the panel, the feed is still centered at its cap', (
      tester,
    ) async {
      final errors = await _pumpDiscover(
        tester,
        const Size(1199, 900),
        nearby: _FakeNearbyRepository(_profiles(4)),
      );
      expectNoOverflowIn(errors);
      // Feed content: 680, centered in 1199, so a 259.5px gutter each side.
      // Near You pads itself 16px inside that.
      expect(tester.getSize(_gridFinder).width, 648);
      expect(tester.getTopLeft(_gridFinder).dx, 275.5);
    });

    testWidgets('lists conversations newest first', (tester) async {
      final errors = await _pumpDiscover(
        tester,
        const Size(1440, 900),
        nearby: _FakeNearbyRepository(_profiles(4)),
        conversations: [
          _conversation('c1', hoursAgo: 3),
          _conversation('c2', hoursAgo: 1),
        ],
      );
      expectNoOverflowIn(errors);
      expect(_inPanel('Member c1'), findsOneWidget);
      expect(_inPanel('Member c2'), findsOneWidget);
      expect(
        tester.getTopLeft(_inPanel('Member c2')).dy,
        lessThan(tester.getTopLeft(_inPanel('Member c1')).dy),
      );
    });

    testWidgets('ignores the Inbox page search and filters, keeps its rules', (
      tester,
    ) async {
      final errors = await _pumpDiscover(
        tester,
        const Size(1440, 900),
        nearby: _FakeNearbyRepository(_profiles(4)),
        conversations: [
          _conversation('c1'),
          _conversation('c2', isArchived: true),
        ],
        extraOverrides: [
          // State a member could have left behind on the Inbox page.
          inboxSearchQueryProvider.overrideWith((ref) => 'nobody matches'),
          inboxFilterProvider.overrideWith((ref) => {InboxFilter.unread}),
        ],
      );
      expectNoOverflowIn(errors);
      expect(_inPanel('Member c1'), findsOneWidget);
      // The Inbox's default view still hides archived conversations.
      expect(_inPanel('Member c2'), findsNothing);
    });

    testWidgets('empty: the inbox empty state, without the Discover button', (
      tester,
    ) async {
      final errors = await _pumpDiscover(
        tester,
        const Size(1440, 900),
        nearby: _FakeNearbyRepository(_profiles(4)),
      );
      expectNoOverflowIn(errors);
      final empty = find.descendant(
        of: _panelFinder,
        matching: find.byType(EmptyInbox),
      );
      expect(empty, findsOneWidget);
      expect(tester.widget<EmptyInbox>(empty).showAction, isFalse);
      expect(
        find.descendant(
          of: _panelFinder,
          matching: find.byType(NmPrimaryButton),
        ),
        findsNothing,
      );
    });

    testWidgets('tapping a conversation opens the existing chat route', (
      tester,
    ) async {
      const size = Size(1440, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.binding.setSurfaceSize(size);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = GoRouter(
        initialLocation: RouteNames.discover,
        routes: [
          GoRoute(
            path: RouteNames.discover,
            builder: (context, state) => const DiscoverPage(),
          ),
          GoRoute(
            path: RouteNames.chatDetailPattern,
            builder: (context, state) => Scaffold(
              body: Text('chat ${state.pathParameters['conversationId']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _discoverOverrides(
            nearby: _FakeNearbyRepository(_profiles(4)),
            conversations: [_conversation('c1'), _conversation('c2')],
          ),
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await tester.tap(_inPanel('Member c2'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('chat c2'), findsOneWidget);
      // Pushed on top of Discover (not a replacement), as the Inbox does.
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        RouteNames.chatDetailPath('c2'),
      );
      expect(router.canPop(), isTrue);
    });
  });
}

// --- helpers ----------------------------------------------------------------

final Finder _gridFinder = find.byType(GridView, skipOffstage: false);

int _columnsOf(WidgetTester tester) => _delegateOf(tester).crossAxisCount;

SliverGridDelegateWithFixedCrossAxisCount _delegateOf(WidgetTester tester) {
  expect(_gridFinder, findsOneWidget);
  return tester.widget<GridView>(_gridFinder).gridDelegate
      as SliverGridDelegateWithFixedCrossAxisCount;
}

List<String> _cardNames(int count) => [
  for (var i = 1; i <= count; i++) 'Person $i, 27',
];

/// How many of the first [count] cards sit on each visual row, top to bottom.
List<int> _rowsOfCards(WidgetTester tester, int count) {
  final rows = <double, int>{};
  for (final name in _cardNames(count)) {
    final dy = tester.getTopLeft(find.text(name, skipOffstage: false)).dy;
    rows.update(dy, (n) => n + 1, ifAbsent: () => 1);
  }
  final ys = rows.keys.toList()..sort();
  return [for (final y in ys) rows[y]!];
}

List<DiscoveryProfileEntity> _profiles(int count) => [
  for (var i = 1; i <= count; i++)
    DiscoveryProfileEntity(
      id: 'n$i',
      matrimonyId: 'n$i',
      name: 'Person $i',
      age: 27,
      location: 'Chennai',
      profession: 'Engineer',
      education: 'B.E.',
      photoUrls: const [],
      distanceKm: 2.0 + i,
      gender: 'Female',
    ),
];

DiscoverFeedEntity _feed() => const DiscoverFeedEntity(
  stories: [],
  profileCompletionPercent: 0,
  aiRecommended: [],
  recentlyJoined: [],
  verifiedProfiles: [],
  nearYou: [],
  premiumMembers: [],
);

/// Pumps the real [DiscoverPage] at [size] with only its data sources faked,
/// and returns the exceptions the pump produced.
///
/// [conversations] feeds the inbox panel shown at large widths; it defaults to
/// none so the Near You assertions see an empty, shimmer-free panel.
Future<List<Object>> _pumpDiscover(
  WidgetTester tester,
  Size size, {
  required NearbyRepository nearby,
  DeviceLocationService? location,
  List<ConversationEntity> conversations = const [],
  List<Override> extraOverrides = const [],
}) {
  return pumpAtSize(
    tester,
    size,
    const DiscoverPage(),
    overrides: [
      ..._discoverOverrides(
        nearby: nearby,
        location: location,
        conversations: conversations,
      ),
      ...extraOverrides,
    ],
  );
}

List<Override> _discoverOverrides({
  required NearbyRepository nearby,
  DeviceLocationService? location,
  List<ConversationEntity> conversations = const [],
}) => [
  deviceLocationServiceProvider.overrideWithValue(
    location ?? _FakeLocationService(_granted),
  ),
  nearbyRepositoryProvider.overrideWithValue(nearby),
  discoverFeedProvider.overrideWith((ref) async => _feed()),
  conversationRepositoryProvider.overrideWithValue(
    _FakeConversationRepository(conversations),
  ),
];

final Finder _panelFinder = find.byType(InboxPreviewPanel);

/// Text inside the inbox panel only, so a name elsewhere on the page can't
/// satisfy the assertion.
Finder _inPanel(String text) =>
    find.descendant(of: _panelFinder, matching: find.text(text));

ConversationEntity _conversation(
  String id, {
  int hoursAgo = 1,
  bool isArchived = false,
}) => ConversationEntity(
  id: id,
  profile: DiscoveryProfileEntity(
    id: 'peer-$id',
    matrimonyId: 'NM-$id',
    name: 'Member $id',
    age: 28,
    location: 'Chennai',
    profession: 'Engineer',
    education: 'B.E.',
    photoUrls: const [],
  ),
  lastMessage: 'hello from $id',
  lastMessageAt: DateTime(2026, 1, 1).subtract(Duration(hours: hoursAgo)),
  isArchived: isArchived,
);

/// Hand-written fake (no mocking library in this repo). Anything the panel
/// does not need is left to `noSuchMethod`, so an unexpected call fails loudly.
class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository(this.conversations);

  final List<ConversationEntity> conversations;

  @override
  Future<ConversationResultPage> getConversations({
    int page = 1,
    int limit = 20,
  }) async => ConversationResultPage(
    items: conversations,
    page: 1,
    limit: limit,
    total: conversations.length,
    hasMore: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _granted = LocationSuccess(
  latitude: 13.0827,
  longitude: 80.2707,
  accuracyMetres: 20,
);

class _FakeLocationService implements DeviceLocationService {
  _FakeLocationService(this.result);

  final LocationResult result;

  @override
  Future<LocationResult?> checkPermissionOnly() async =>
      result is LocationSuccess ? null : result;

  @override
  Future<LocationResult> requestAndFetch() async => result;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _FakeNearbyRepository implements NearbyRepository {
  _FakeNearbyRepository(this.profiles, {this.throwOnFetch = false, this.gate});

  final List<DiscoveryProfileEntity> profiles;
  final bool throwOnFetch;

  /// When set, a fetch waits on it, holding the section in its loading state.
  final Completer<void>? gate;

  @override
  Future<List<DiscoveryProfileEntity>> getNearbyProfiles({
    required double latitude,
    required double longitude,
    double radiusKm = 100,
    int page = 1,
    int limit = 50,
  }) async {
    await gate?.future;
    if (throwOnFetch) throw Exception('network down');
    return profiles;
  }

  @override
  Future<void> updateMyLocation({
    required double latitude,
    required double longitude,
    int? accuracyMetres,
  }) async {}
}
