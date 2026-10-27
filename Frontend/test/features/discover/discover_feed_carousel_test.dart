import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/location/device_location_service.dart';
import 'package:nenjam_matrimony/core/services/location/location_providers.dart';
import 'package:nenjam_matrimony/features/discover/data/repositories/discover_repository_impl.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/presentation/pages/discover_page.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/inbox/domain/entities/conversation_entity.dart';
import 'package:nenjam_matrimony/features/inbox/domain/repositories/conversation_repository.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/widgets/inbox_preview_panel.dart';
import 'package:nenjam_matrimony/features/nearby/domain/repositories/nearby_repository.dart';
import 'package:nenjam_matrimony/features/nearby/presentation/providers/nearby_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import '../../support/responsive_harness.dart';

/// Discover showed a single profile however many the backend returned.
///
/// The feed is one `/discover` page partitioned into sections, and Verified,
/// Premium, Recently Joined and New Today only take members who qualify.
/// Everyone else — on a typical feed, nearly everyone — lands in AI
/// Recommended, which rendered `aiRecommended.first` and nothing else.
///
/// These run the real [DiscoverRepositoryImpl] over a stubbed [ApiClient], so
/// the partitioning that produced the bug is part of what is tested, not
/// assumed away by a hand-built feed.
void main() {
  group('every profile the backend returns is reachable', () {
    testWidgets('twelve ordinary members: all twelve, one card at a time', (
      tester,
    ) async {
      final api = _FeedApi(firstPage: _page(_members(1, 12)));
      expectNoOverflowIn(await _pump(tester, const Size(390, 844), api));

      expect(_position, findsOneWidget);
      expect(find.text('1 of 12'), findsOneWidget);
      expect(_name(1), findsOneWidget);

      for (var i = 2; i <= 12; i++) {
        await _next(tester);
        expect(find.text('$i of 12'), findsOneWidget);
        expect(_name(i), findsOneWidget, reason: 'card $i after next');
      }

      // At the last card of an exhausted feed, next is disabled.
      expect(_nextButton(tester).onPressed, isNull);
      await _previous(tester);
      expect(find.text('11 of 12'), findsOneWidget);
      expect(_name(11), findsOneWidget);
    });

    testWidgets('a swipe moves to the next profile', (tester) async {
      final api = _FeedApi(firstPage: _page(_members(1, 5)));
      expectNoOverflowIn(await _pump(tester, const Size(390, 844), api));

      await tester.drag(_cardPager, const Offset(-300, 0));
      await _settle(tester);

      expect(find.text('2 of 5'), findsOneWidget);
      expect(_name(2), findsOneWidget);
    });

    testWidgets('one profile: one card and no carousel controls', (
      tester,
    ) async {
      final api = _FeedApi(firstPage: _page(_members(1, 1)));
      expectNoOverflowIn(await _pump(tester, const Size(390, 844), api));

      expect(_name(1), findsOneWidget);
      expect(_position, findsNothing);
    });

    testWidgets('verified members are browsable in their own section', (
      tester,
    ) async {
      final api = _FeedApi(
        firstPage: _page([
          for (var i = 1; i <= 10; i++) _member(i, verified: true),
        ]),
      );
      expectNoOverflowIn(await _pump(tester, const Size(390, 844), api));

      // Round-robin over 5 sections with nobody new or premium: m2, m3, m7
      // and m8 land in Verified Profiles, the other six in AI Recommended.
      expect(
        find.text('Verified Profiles', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('1 of 6', skipOffstage: false), findsOneWidget);
      expect(
        find.text('1 of 4', skipOffstage: false),
        findsOneWidget,
        reason: 'the Verified carousel holds all four of its members',
      );
    });
  });

  group('next pages', () {
    testWidgets('nearing the end loads the next page by cursor', (
      tester,
    ) async {
      final api = _FeedApi(
        firstPage: _page(_members(1, 5), nextCursor: 'c1'),
        pages: {'c1': _page(_members(6, 9))},
      );
      expectNoOverflowIn(await _pump(tester, const Size(390, 844), api));
      expect(find.text('1 of 5'), findsOneWidget);
      expect(api.cursors, isEmpty, reason: 'nothing prefetched on arrival');

      await _next(tester); // 2 of 5: still 3 from the end
      expect(api.cursors, isEmpty);

      await _next(tester); // 3 of 5: within 3 of the end -> prefetch
      expect(api.cursors, ['c1']);
      expect(find.text('3 of 9'), findsOneWidget);

      for (var i = 4; i <= 9; i++) {
        await _next(tester);
      }
      expect(find.text('9 of 9'), findsOneWidget);
      expect(_name(9), findsOneWidget);
      // The second page reported no cursor: the feed is exhausted.
      expect(api.cursors, ['c1']);
      expect(_nextButton(tester).onPressed, isNull);
    });

    testWidgets('next on the last card asks for more when there is more', (
      tester,
    ) async {
      final api = _FeedApi(
        firstPage: _page(_members(1, 1), nextCursor: 'c1'),
        pages: {'c1': _page(_members(2, 3))},
      );
      expectNoOverflowIn(await _pump(tester, const Size(390, 844), api));
      expect(find.text('1 of 1'), findsOneWidget);
      expect(_nextButton(tester).onPressed, isNotNull);

      await _next(tester);
      expect(api.cursors, ['c1']);
      expect(find.text('1 of 3'), findsOneWidget);

      await _next(tester);
      expect(_name(2), findsOneWidget);
    });

    testWidgets('profiles already on screen are never shown twice', (
      tester,
    ) async {
      final api = _FeedApi(
        firstPage: _page(_members(1, 4), nextCursor: 'c1'),
        // A ranking that shifted between requests: 3 and 4 come back again,
        // and 5 is repeated within the page itself.
        pages: {
          'c1': _page([
            _member(3),
            _member(4),
            _member(5),
            _member(5),
            _member(6),
          ]),
        },
      );
      expectNoOverflowIn(await _pump(tester, const Size(390, 844), api));

      await _next(tester); // 2 of 4: within 3 of the end -> prefetch
      expect(find.text('2 of 6'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DiscoverPage)),
      );
      final feed = container.read(discoverFeedProvider).requireValue;
      final shown = [
        ...feed.aiRecommended.map((p) => p.id),
        ...container
            .read(discoverMoreProfilesProvider)
            .profiles
            .map((p) => p.id),
      ];
      expect(shown, ['m1', 'm2', 'm3', 'm4', 'm5', 'm6']);
    });

    testWidgets('a failed page keeps what is loaded and offers a retry', (
      tester,
    ) async {
      final api = _FeedApi(
        firstPage: _page(_members(1, 2), nextCursor: 'c1'),
        pages: {'c1': _page(_members(3, 4))},
        failCursorOnce: 'c1',
      );
      expectNoOverflowIn(await _pump(tester, const Size(390, 844), api));

      await _next(tester); // prefetch fails
      expect(find.text("Couldn't load more profiles."), findsOneWidget);
      expect(_name(2), findsOneWidget, reason: 'loaded cards survive');

      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await _settle(tester);
      expect(find.text('2 of 4'), findsOneWidget);
      expect(api.cursors, ['c1', 'c1']);
    });

    testWidgets('a refresh drops appended pages and starts over', (
      tester,
    ) async {
      final api = _FeedApi(
        firstPage: _page(_members(1, 3), nextCursor: 'c1'),
        pages: {'c1': _page(_members(4, 6))},
      );
      expectNoOverflowIn(await _pump(tester, const Size(390, 844), api));
      await _next(tester);
      expect(find.text('2 of 6'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DiscoverPage)),
      );
      container.invalidate(discoverFeedProvider);
      await _settle(tester);

      expect(container.read(discoverMoreProfilesProvider).profiles, isEmpty);
      expect(find.textContaining(' of 3'), findsOneWidget);
      expect(api.feedRequests, 2);
    });
  });

  group('non-result states', () {
    testWidgets('an empty feed shows the empty state, not a card', (
      tester,
    ) async {
      final api = _FeedApi(firstPage: _page(const []));
      expectNoOverflowIn(await _pump(tester, const Size(390, 844), api));

      expect(find.text('No matching profiles found.'), findsOneWidget);
      expect(_cardPager, findsNothing);
    });

    testWidgets('a failed first load shows retry, and retry recovers', (
      tester,
    ) async {
      final api = _FeedApi(
        firstPage: _page(_members(1, 3)),
        failFirstFeed: true,
      );
      expectNoOverflowIn(await _pump(tester, const Size(390, 844), api));

      expect(_cardPager, findsNothing);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.text('1 of 3'), findsOneWidget);
    });
  });

  group('layout at the brief sizes', () {
    for (final size in const [
      Size(320, 568),
      Size(568, 320),
      Size(768, 1024),
      Size(1024, 768),
      Size(1366, 768),
      Size(1440, 900),
    ]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('$label: no overflow, actions on screen and tappable', (
        tester,
      ) async {
        final api = _FeedApi(firstPage: _page(_members(1, 12)));
        expectNoOverflowIn(await _pump(tester, size, api));

        // The feed column never exceeds its 680px cap and never spills.
        final pager = tester.getRect(_cardPager);
        expect(pager.left, greaterThanOrEqualTo(0));
        expect(pager.width, lessThanOrEqualTo(680));
        final feedRight = size.width >= 1200
            ? size.width - InboxPreviewPanel.width
            : size.width;
        expect(pager.right, lessThanOrEqualTo(feedRight));

        // Inbox preview only beside a wide feed.
        expect(
          find.byType(InboxPreviewPanel),
          size.width >= 1200 ? findsOneWidget : findsNothing,
        );

        // Bring the card's actions into view the way a member would, then
        // check each sits below the sticky bar and inside the window, at full
        // size, and actually receives a tap at its center.
        await _reveal(tester, _viewProfile);
        await _settle(tester);
        const appBarBottom = 44 + 64.0; // status bar inset + toolbar
        for (final action in [_interested, _shortlist, _viewProfile]) {
          final r = tester.getRect(action);
          expect(r.top, greaterThanOrEqualTo(appBarBottom), reason: '$action');
          expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$action');
          _expectHittable(tester, action);
        }
        // Not shrunk by the card's scale-down guard: real touch targets.
        expect(tester.getRect(_interestedButton).height, closeTo(54, 0.5));

        // On any window tall enough, the whole card and its controls fit
        // between the sticky bar and the bottom inset at once.
        if (size.height >= 700) {
          final card = tester.getRect(_cardPager);
          final controls = tester.getRect(_position);
          expect(
            controls.bottom - card.top,
            lessThanOrEqualTo(size.height - appBarBottom - 34),
          );
        }

        // Navigable at every size.
        await _next(tester);
        expect(find.text('2 of 12'), findsOneWidget);
        expect(_name(2), findsOneWidget);
      });
    }

    testWidgets('Tamil at 320x568: no overflow', (tester) async {
      final api = _FeedApi(firstPage: _page(_members(1, 3)));
      expectNoOverflowIn(
        await _pump(
          tester,
          const Size(320, 568),
          api,
          locale: const Locale('ta'),
        ),
      );
      expect(_cardPager, findsOneWidget);
    });
  });

  testWidgets('View Profile on a later card opens that member', (tester) async {
    const size = Size(390, 844);
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
          path: RouteNames.profileDetailPattern,
          builder: (context, state) => Scaffold(
            body: Text('detail ${state.pathParameters['profileId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(_FeedApi(firstPage: _page(_members(1, 4)))),
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await _settle(tester);

    await _next(tester);
    await _next(tester);
    await _reveal(tester, _viewProfile);
    await _settle(tester);
    await tester.tap(_viewProfile);
    await _settle(tester);

    expect(find.text('detail m3'), findsOneWidget);
  });
}

// --- finders ----------------------------------------------------------------

final Finder _cardPager = find.byType(PageView);
final Finder _position = find.textContaining(RegExp(r'^\d+ of \d+$'));
final Finder _viewProfile = find.descendant(
  of: _cardPager,
  matching: find.text('View Profile'),
);
final Finder _shortlist = find.descendant(
  of: _cardPager,
  matching: find.text('Shortlist'),
);
final Finder _interested = find.descendant(
  of: _cardPager,
  matching: find.byIcon(Icons.favorite_rounded),
);

/// The 54px gradient button around the heart icon.
final Finder _interestedButton = find
    .ancestor(of: _interested, matching: find.byType(InkWell))
    .first;

Finder _name(int i) =>
    find.text('${_names[(i - 1) % _names.length]}, ${26 + i % 6}');

IconButton _nextButton(WidgetTester tester) => tester.widget<IconButton>(
  find
      .ancestor(
        of: find.byIcon(Icons.chevron_right_rounded),
        matching: find.byType(IconButton),
      )
      .first,
);

Future<void> _next(WidgetTester tester) async {
  await _reveal(tester, find.byTooltip('Next profile').first);
  await tester.tap(find.byTooltip('Next profile').first);
  await _settle(tester);
}

Future<void> _previous(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Previous profile').first);
  await _settle(tester);
}

/// Scrolls [finder] into view with its bottom at the bottom of the viewport.
/// `ensureVisible`'s default aligns the top edge, which leaves the target
/// under the pinned app bar, where a tap would land on the bar instead.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  Scrollable.ensureVisible(tester.element(finder), alignment: 1.0);
  await _settle(tester);
}

/// Bounded pumps rather than pumpAndSettle: shimmer placeholders repeat.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A tap at [finder]'s center reaches it — nothing (the sticky app bar, an
/// overlapping panel) sits on top of it.
void _expectHittable(WidgetTester tester, Finder finder) {
  final target = tester.renderObject(finder);
  final hit = tester.hitTestOnBinding(tester.getCenter(finder));
  expect(
    hit.path.any((entry) => entry.target == target),
    isTrue,
    reason: '$finder is covered at its center',
  );
}

// --- fixtures ---------------------------------------------------------------

const _names = [
  'Meera Krishnan',
  'Lakshmi Narayanan',
  'Divya Ramasamy',
  'Kavitha Sundaram',
  'Priya Venkatesan',
  'Anitha Balasubramanian',
  'Revathi Murugan',
  'Sangeetha Raghavan',
  'Nandhini Selvaraj',
  'Harini Ganesan',
  'Janani Arumugam',
  'Swathi Chandrasekaran',
];

const _cities = ['Chennai', 'Coimbatore', 'Madurai', 'Tiruchirappalli'];

/// A member as `/discover` sends them: joined two months ago, so not "new",
/// and neither verified nor premium unless asked — the common case, and the
/// one that put every profile into AI Recommended.
Map<String, dynamic> _member(int i, {bool verified = false}) => {
  'id': 'm$i',
  'matrimonyId': 'NM10${i.toString().padLeft(3, '0')}',
  'name': _names[(i - 1) % _names.length],
  'age': 26 + i % 6,
  'location': '${_cities[i % _cities.length]}, Tamil Nadu',
  'profession': 'Software Engineer',
  'education': 'B.E. Computer Science',
  'photoUrls': <String>[],
  'gender': 'female',
  'religion': 'Hindu',
  'motherTongue': 'Tamil',
  'isVerified': verified,
  'isPremium': false,
  'joinedAt': DateTime.now()
      .subtract(const Duration(days: 60))
      .toUtc()
      .toIso8601String(),
};

List<Map<String, dynamic>> _members(int from, int to) => [
  for (var i = from; i <= to; i++) _member(i),
];

Map<String, dynamic> _page(
  List<Map<String, dynamic>> items, {
  String? nextCursor,
}) => {
  'items': items,
  'page': 1,
  'limit': 50,
  'hasMore': nextCursor != null,
  'nextCursor': nextCursor,
  'fallbackUsed': false,
  'reason': '',
};

/// `/discover`, served from fixtures. The first request (no cursor) is the
/// sectioned feed's page; later requests are looked up by cursor.
class _FeedApi extends ApiClient {
  _FeedApi({
    required this.firstPage,
    this.pages = const {},
    this.failFirstFeed = false,
    this.failCursorOnce,
  });

  final Map<String, dynamic> firstPage;
  final Map<String, Map<String, dynamic>> pages;
  bool failFirstFeed;
  String? failCursorOnce;

  final List<String> cursors = [];
  int feedRequests = 0;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final cursor = queryParameters?['cursor'] as String?;
    if (cursor == null) {
      feedRequests++;
      if (failFirstFeed) {
        failFirstFeed = false;
        throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError,
        );
      }
      return _ok<T>(path, firstPage);
    }
    cursors.add(cursor);
    if (failCursorOnce == cursor) {
      failCursorOnce = null;
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    return _ok<T>(path, pages[cursor] ?? _page(const []));
  }

  Response<T> _ok<T>(String path, Map<String, dynamic> body) => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: body as T?,
  );
}

Future<List<Object>> _pump(
  WidgetTester tester,
  Size size,
  _FeedApi api, {
  Locale locale = const Locale('en'),
}) => pumpAtSize(
  tester,
  size,
  const DiscoverPage(),
  overrides: _overrides(api),
  locale: locale,
);

List<Override> _overrides(_FeedApi api) => [
  discoverRepositoryProvider.overrideWithValue(DiscoverRepositoryImpl(api)),
  deviceLocationServiceProvider.overrideWithValue(_GrantedLocation()),
  nearbyRepositoryProvider.overrideWithValue(_NobodyNearby()),
  conversationRepositoryProvider.overrideWithValue(_NoConversations()),
];

class _GrantedLocation implements DeviceLocationService {
  static const _here = LocationSuccess(
    latitude: 13.0827,
    longitude: 80.2707,
    accuracyMetres: 20,
  );

  @override
  Future<LocationResult?> checkPermissionOnly() async => null;

  @override
  Future<LocationResult> requestAndFetch() async => _here;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _NobodyNearby implements NearbyRepository {
  @override
  Future<List<DiscoveryProfileEntity>> getNearbyProfiles({
    required double latitude,
    required double longitude,
    double radiusKm = 100,
    int page = 1,
    int limit = 50,
  }) async => const [];

  @override
  Future<void> updateMyLocation({
    required double latitude,
    required double longitude,
    int? accuracyMetres,
  }) async {}
}

class _NoConversations implements ConversationRepository {
  @override
  Future<ConversationResultPage> getConversations({
    int page = 1,
    int limit = 20,
  }) async => ConversationResultPage(
    items: const <ConversationEntity>[],
    page: 1,
    limit: limit,
    total: 0,
    hasMore: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
