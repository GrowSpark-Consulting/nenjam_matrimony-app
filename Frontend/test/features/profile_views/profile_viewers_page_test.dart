import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/profile_views/domain/entities/profile_viewer_entity.dart';
import 'package:nenjam_matrimony/features/profile_views/domain/repositories/profile_views_repository.dart';
import 'package:nenjam_matrimony/features/profile_views/presentation/pages/profile_viewers_page.dart';
import 'package:nenjam_matrimony/features/profile_views/presentation/providers/profile_views_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Back behaviour of Profile Viewers, which differs by how the page was
/// reached — see [ProfileViewersPage]'s doc comment.
///
/// Every case is exercised twice where it matters: once through the AppBar
/// button and once through Android's system back, because those are separate
/// code paths (`onPressed` vs `PopScope.onPopInvokedWithResult`) and a fix to
/// one has historically missed the other.
void main() {
  group('ProfileViewersPage back navigation', () {
    testWidgets('pushed from the drawer, Back returns to the previous screen',
        (tester) async {
      final router = await _pump(tester, initialLocation: RouteNames.discover);

      router.push(RouteNames.profileViewers);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileViewersPage), findsOneWidget);

      await _tapBack(tester);

      expect(router.state.matchedLocation, RouteNames.discover);
      expect(find.byType(ProfileViewersPage), findsNothing);
    });

    testWidgets('pushed from a notification, Back returns to Notifications',
        (tester) async {
      final router = await _pump(
        tester,
        initialLocation: RouteNames.notifications,
      );

      router.push(_notificationPath);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileViewersPage), findsOneWidget);

      await _tapBack(tester);

      expect(router.state.matchedLocation, RouteNames.notifications);
    });

    testWidgets('Android back returns to Notifications too', (tester) async {
      final router = await _pump(
        tester,
        initialLocation: RouteNames.notifications,
      );

      router.push(_notificationPath);
      await tester.pumpAndSettle();

      await _systemBack(tester);

      expect(router.state.matchedLocation, RouteNames.notifications);
    });

    group('cold start — the page is the whole stack', () {
      testWidgets('AppBar Back falls back to Notifications when the tap came '
          'from one', (tester) async {
        final router = await _pump(tester, initialLocation: _notificationPath);
        expect(router.canPop(), isFalse);

        await _tapBack(tester);

        expect(router.state.matchedLocation, RouteNames.notifications);
      });

      testWidgets('Android back falls back to Notifications too',
          (tester) async {
        final router = await _pump(tester, initialLocation: _notificationPath);

        await _systemBack(tester);

        expect(router.state.matchedLocation, RouteNames.notifications);
      });

      testWidgets('without the notification flag it falls back to Discover',
          (tester) async {
        // A direct link to the bare path — Notifications would be a
        // confusing place to land when no notification was involved.
        final router = await _pump(
          tester,
          initialLocation: RouteNames.profileViewers,
        );

        await _tapBack(tester);

        expect(router.state.matchedLocation, RouteNames.discover);
      });
    });
  });
}

/// The path the notification service pushes.
const String _notificationPath =
    '${RouteNames.profileViewers}?${RouteNames.openedFromNotificationParam}=true';

Future<void> _tapBack(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back));
  await tester.pumpAndSettle();
}

/// Drives the Android hardware/gesture back, which reaches the app as a
/// `popRoute` platform message rather than as a tap.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Pumps the real [ProfileViewersPage] over stub Discover/Notifications
/// routes, wired the same way [RouteNames] wires them in the app router.
Future<GoRouter> _pump(
  WidgetTester tester, {
  required String initialLocation,
}) async {
  GoRoute stub(String path) => GoRoute(
        path: path,
        builder: (_, __) => Scaffold(body: Text('stub $path')),
      );

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      stub(RouteNames.discover),
      stub(RouteNames.notifications),
      GoRoute(
        path: RouteNames.profileViewers,
        builder: (context, state) => ProfileViewersPage(
          openedFromNotification: state.uri
                  .queryParameters[RouteNames.openedFromNotificationParam] ==
              'true',
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileViewsRepositoryProvider
            .overrideWithValue(_EmptyProfileViewsRepository()),
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

/// No viewers — the list's contents are irrelevant to back navigation, and an
/// empty result renders without needing a fixture profile.
class _EmptyProfileViewsRepository implements ProfileViewsRepository {
  @override
  Future<List<ProfileViewerEntity>> getViewers({int page = 1, int limit = 20}) async =>
      const [];

  @override
  Future<void> recordView(String profileId) async {}
}
