import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/notifications/domain/repositories/notification_repository.dart';
import 'package:nenjam_matrimony/features/notifications/presentation/pages/notifications_page.dart';
import 'package:nenjam_matrimony/features/notifications/presentation/providers/notification_providers.dart';
import 'package:nenjam_matrimony/features/notifications/presentation/services/notification_navigation_service.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Notifications keeps its back arrow across a trip to Profile Viewers.
///
/// [NotificationsPage]'s AppBar sets no `leading` and no
/// `automaticallyImplyLeading`, so the arrow is drawn if and only if the route
/// can pop. That made the arrow a direct readout of the navigation stack — and
/// the stack was being destroyed underneath it.
///
/// Tapping a PROFILE_VIEW row inside the Notification Center routes through
/// [NotificationNavigationService], the same service a system-tray tap uses.
/// For that type the service did `goNamed(notifications)` and then
/// `pushNamed(profileViewers)`. The `go` exists for the tray case, where
/// Notifications is not on screen yet and has to be established beneath the
/// viewers list. But when the member was *already* on Notifications, `go` to
/// the location you are already at is not a no-op: it rebuilds the stack as
/// that one route, discarding the Discover entry the member had pushed
/// Notifications from. Popping the viewers list then landed on a Notifications
/// page with nothing beneath it, and the arrow was simply gone.
///
/// These pin the whole round trip at the widget level — the arrow itself, not
/// a proxy for it — plus the stack facts that explain it.
void main() {
  Future<GoRouter> pump(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: RouteNames.discover,
      routes: [
        GoRoute(
          path: RouteNames.discover,
          name: RouteNames.discoverName,
          builder: (_, __) => const Scaffold(body: Text('discover')),
        ),
        GoRoute(
          path: RouteNames.notifications,
          name: RouteNames.notificationsName,
          builder: (_, __) => const NotificationsPage(),
        ),
        GoRoute(
          path: RouteNames.profileViewers,
          name: RouteNames.profileViewersName,
          builder: (_, __) => const Scaffold(body: Text('viewers')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider
              .overrideWithValue(_EmptyNotificationRepository()),
          notificationNavigationServiceProvider.overrideWith(
            (ref) => NotificationNavigationService(
              ref,
              routerResolver: () => router,
            ),
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  /// How Flutter itself decides to draw the arrow, asserted the same way.
  bool backArrowShowing(WidgetTester tester) =>
      find.byType(BackButton).evaluate().isNotEmpty;

  int stackDepth(GoRouter router) =>
      router.routerDelegate.currentConfiguration.matches.length;

  String location(GoRouter router) => router.state.matchedLocation;

  testWidgets('the arrow survives Notifications -> Viewers -> Back',
      (tester) async {
    final router = await pump(tester);

    // The member opens Notifications from Discover, as the bell does.
    router.push(RouteNames.notifications);
    await tester.pumpAndSettle();

    expect(location(router), RouteNames.notifications);
    expect(backArrowShowing(tester), isTrue,
        reason: 'the arrow must be there before we go anywhere');
    final depthBefore = stackDepth(router);
    expect(depthBefore, greaterThan(1),
        reason: 'Discover must still be underneath');

    // Tapping a PROFILE_VIEW row goes through the service, exactly as the
    // in-app list does (NotificationCard._handleTap -> service.handle).
    final service = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(notificationNavigationServiceProvider);
    service.handle({'type': 'PROFILE_VIEW'});
    await tester.pumpAndSettle();

    expect(location(router), RouteNames.profileViewers);

    // Back out of the viewers list.
    router.pop();
    await tester.pumpAndSettle();

    expect(location(router), RouteNames.notifications);
    expect(
      backArrowShowing(tester),
      isTrue,
      reason: 'the arrow disappeared — the stack beneath Notifications was '
          'discarded by a go() to the route already on screen',
    );
    expect(stackDepth(router), depthBefore,
        reason: 'the stack must be exactly what it was before the trip');
  });

  testWidgets('no duplicate Notifications route is created', (tester) async {
    final router = await pump(tester);

    router.push(RouteNames.notifications);
    await tester.pumpAndSettle();

    final service = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(notificationNavigationServiceProvider);
    service.handle({'type': 'PROFILE_VIEW'});
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();

    final notificationMatches = router
        .routerDelegate.currentConfiguration.matches
        .where((m) => m.matchedLocation == RouteNames.notifications)
        .length;
    expect(notificationMatches, 1,
        reason: 'Notifications must appear once, not stacked on itself');
  });

  testWidgets('a tray tap with Notifications not on screen still nests it',
      (tester) async {
    // The case the go() was written for must keep working: from Discover,
    // the viewers list has to land on top of Notifications so Back goes
    // there rather than out of the app.
    final router = await pump(tester);

    expect(location(router), RouteNames.discover);

    final service = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(notificationNavigationServiceProvider);
    service.handle({'type': 'PROFILE_VIEW'});
    await tester.pumpAndSettle();

    expect(location(router), RouteNames.profileViewers);

    router.pop();
    await tester.pumpAndSettle();

    expect(location(router), RouteNames.notifications);
  });
}

class _EmptyNotificationRepository implements NotificationRepository {
  @override
  Future<NotificationResultPage> getNotifications({
    int page = 1,
    int limit = 20,
  }) async =>
      const NotificationResultPage(
        items: [],
        page: 1,
        limit: 20,
        total: 0,
        hasMore: false,
      );

  @override
  Future<int> getUnreadCount() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
