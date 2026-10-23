import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/layout/rail_inset.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/theme/app_theme.dart';
import 'package:nenjam_matrimony/core/widgets/navigation/app_bottom_nav.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:nenjam_matrimony/features/notifications/presentation/providers/notification_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'support/responsive_harness.dart';

/// The app's navigation at every window class: phones and narrow tablets keep
/// the bottom pill at full width; from 900px the app-level [NmDesktopFrame]
/// draws one 96px rail beside every signed-in page — the tabs and the pages
/// pushed over them — and none on public routes. Content is whatever is left
/// of the window after the rail; it is never capped.
const _probe = ValueKey('probe');
const _rail = ValueKey('desktop-nav-rail');
const _tabPaths = ['/a', '/b', '/c', '/d'];

double _expectedRailWidth(double width) => width >= 900 ? 96 : 0;

/// The tabs in a real [AppBottomNavShell], a page pushed over them, the
/// footer destinations, and one public route — under the frame, exactly as
/// main.dart installs it.
Future<GoRouter> _pump(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  Widget page(String name) => Scaffold(
    body: SizedBox.expand(key: _probe, child: Text('page $name')),
  );

  final router = GoRouter(
    initialLocation: '/a',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            AppBottomNavShell(navigationShell: shell),
        branches: [
          for (final path in _tabPaths)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: path,
                  builder: (context, state) =>
                      const SizedBox.expand(key: _probe),
                ),
              ],
            ),
        ],
      ),
      GoRoute(path: '/pushed', builder: (context, state) => page('pushed')),
      for (final path in [
        RouteNames.notifications,
        RouteNames.profile,
        RouteNames.profileMenu,
      ])
        GoRoute(path: path, builder: (context, state) => page(path)),
      // Public: no rail.
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) => page('login'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        unreadMessagesCountProvider.overrideWithValue(3),
        unreadNotificationsCountProvider.overrideWithValue(2),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        locale: locale,
        routerConfig: router,
        builder: (context, child) =>
            NmDesktopFrame(router: router, tabPaths: _tabPaths, child: child!),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

/// The pill's own label row; the rail's labels live under [_rail].
Finder _pillLabel(String text) => find.descendant(
  of: find.byType(AppBottomNavShell),
  matching: find.text(text),
);

Finder _railLabel(String text) =>
    find.descendant(of: find.byKey(_rail), matching: find.text(text));

void main() {
  group('navigation affordance by window class', () {
    // The boundary widths plus the two common desktop sizes.
    for (final width in [...kBoundaryWidths, 1440.0, 1920.0]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        await _pump(tester, Size(width, 900));
        expect(tester.takeException(), isNull);

        if (width >= 900) {
          expect(find.byKey(_rail), findsOneWidget);
          expect(_pillLabel('Discover'), findsNothing, reason: 'never both');
        } else {
          expect(find.byKey(_rail), findsNothing);
          expect(_pillLabel('Discover'), findsOneWidget);
        }
        expect(
          tester.getSize(find.byKey(_probe)).width,
          width - _expectedRailWidth(width),
          reason: 'content fills the window minus the rail, uncapped',
        );
      });
    }
  });

  testWidgets('the rail runs the full height of the left edge', (tester) async {
    await _pump(tester, const Size(1440, 900));
    expect(
      tester.getRect(find.byKey(_rail)),
      const Rect.fromLTWH(0, 0, 96, 900),
    );
    // Footer pinned to the bottom, tabs near the top.
    expect(tester.getTopLeft(_railLabel('Discover')).dy, lessThan(200));
    expect(tester.getBottomLeft(_railLabel('More')).dy, greaterThan(800));
  });

  group('pages pushed over the tabs', () {
    testWidgets('keep the rail beside them', (tester) async {
      final router = await _pump(tester, const Size(1440, 900));
      router.push('/pushed');
      await tester.pumpAndSettle();
      expect(find.text('page pushed'), findsOneWidget);
      expect(find.byKey(_rail), findsOneWidget);
      expect(tester.getTopLeft(find.text('page pushed')).dx, 96);
    });

    testWidgets('report the rail to layout that measures the window', (
      tester,
    ) async {
      final router = await _pump(tester, const Size(1440, 900));
      router.push('/pushed');
      await tester.pumpAndSettle();
      final context = tester.element(find.text('page pushed'));
      expect(NmRailInset.of(context), 96);
    });

    testWidgets('a rail tab leaves them for that tab', (tester) async {
      final router = await _pump(tester, const Size(1440, 900));
      router.push('/pushed');
      await tester.pumpAndSettle();
      await tester.tap(_railLabel('Matches'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_location(router), '/b');
      expect(find.text('page pushed'), findsNothing);
    });
  });

  testWidgets('public routes get no rail', (tester) async {
    final router = await _pump(tester, const Size(1440, 900));
    router.go(RouteNames.login);
    await tester.pumpAndSettle();
    expect(find.byKey(_rail), findsNothing);
    expect(tester.getSize(find.byKey(_probe)).width, 1440);
  });

  group('rail destinations', () {
    testWidgets('tabs switch branches', (tester) async {
      final router = await _pump(tester, const Size(1440, 900));
      await tester.tap(_railLabel('Premium'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_location(router), '/d');
    });

    testWidgets('notifications, profile and more open their pages', (
      tester,
    ) async {
      final router = await _pump(tester, const Size(1440, 900));
      for (final (label, path) in [
        ('Notifications', RouteNames.notifications),
        ('Profile', RouteNames.profile),
        ('More', RouteNames.profileMenu),
      ]) {
        await tester.tap(_railLabel(label));
        await tester.pumpAndSettle();
        expect(_location(router), path, reason: label);
      }
      // Pushed, so Back returns through them.
      expect(router.canPop(), isTrue);
    });

    testWidgets('badges are announced with their item', (tester) async {
      await _pump(tester, const Size(1440, 900));
      expect(
        find.bySemanticsLabel(RegExp('Inbox, 3 unread messages')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Notifications, 2')),
        findsOneWidget,
      );
    });
  });

  group('phones keep the floating pill at full width', () {
    for (final size in const [Size(320, 640), Size(375, 812)]) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        final router = await _pump(tester, size);
        expect(tester.takeException(), isNull);
        expect(find.byKey(_rail), findsNothing);
        expect(tester.getSize(find.byKey(_probe)).width, size.width);
        expect(
          find.bySemanticsLabel(RegExp('Inbox, 3 unread messages')),
          findsOneWidget,
        );
        await tester.tap(_pillLabel('Matches'));
        await tester.pumpAndSettle();
        expect(_location(router), '/b');
      });
    }
  });

  testWidgets('long Tamil labels fit the rail without overflow', (
    tester,
  ) async {
    await _pump(tester, const Size(900, 800), locale: const Locale('ta'));
    expectNoOverflowIn(drainExceptions(tester));
    expect(_railLabel('பொருத்தங்கள்'), findsOneWidget);
    expect(_railLabel('மேலும்'), findsOneWidget);
  });

  testWidgets('rail and page remain usable on a short window', (tester) async {
    await _pump(tester, kShortDesktop);
    expect(find.byKey(_rail), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Every item stays reachable: the rail scrolls instead of overflowing.
    expect(find.text('More', skipOffstage: false), findsOneWidget);
  });

  testWidgets('the page keeps its state while the rail comes and goes', (
    tester,
  ) async {
    final router = await _pump(tester, const Size(360, 800));
    router.push('/pushed');
    await tester.pumpAndSettle();
    for (final width in [...kBoundaryWidths, ...kBoundaryWidths.reversed]) {
      expectNoOverflowIn(await resizeTo(tester, Size(width, 800)));
      // Still on the pushed page: the Navigator was not rebuilt.
      expect(_location(router), '/pushed', reason: '${width.toInt()}px');
      expect(
        tester.getSize(find.byKey(_probe)).width,
        width - _expectedRailWidth(width),
        reason: 'after resizing to ${width.toInt()}px',
      );
    }
  });
}
