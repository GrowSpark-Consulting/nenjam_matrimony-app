import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/theme/app_theme.dart';
import 'package:nenjam_matrimony/core/widgets/navigation/app_bottom_nav.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'support/responsive_harness.dart';

/// The navigation shell at every window class: phones keep the bottom pill and
/// the full width, 900-1199 gets the 96px icon rail, 1200+ gets the 240px
/// extended rail. Content is whatever is left of the window after the rail; it
/// is never capped.
const _probe = ValueKey('probe');
const _rail = ValueKey('desktop-nav-rail');
const _extendedRail = ValueKey('desktop-nav-rail-extended');

/// The rail width expected at [width]: 0 below 900 (the pill overlays the
/// content via extendBody, so nothing is subtracted).
double _expectedRailWidth(double width) {
  if (width >= 1200) return NavRailMetrics.extendedWidth;
  if (width >= 900) return NavRailMetrics.compactWidth;
  return 0;
}

Future<GoRouter> _pump(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/a',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            AppBottomNavShell(navigationShell: shell),
        branches: [
          for (final path in ['/a', '/b', '/c', '/d'])
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
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [unreadMessagesCountProvider.overrideWithValue(3)],
      child: MaterialApp.router(
        theme: AppTheme.light,
        locale: locale,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _path(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  group('shell navigation affordance by window class', () {
    // The boundary widths plus the two common desktop sizes.
    for (final width in [...kBoundaryWidths, 1440.0, 1920.0]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        await _pump(tester, Size(width, 900));
        expect(tester.takeException(), isNull);

        final rail = find.byKey(_rail);
        final extended = find.byKey(_extendedRail);
        final probe = tester.getSize(find.byKey(_probe));

        if (width >= 1200) {
          expect(rail, findsOneWidget, reason: 'extended rail at large');
          expect(extended, findsOneWidget);
        } else if (width >= 900) {
          expect(rail, findsOneWidget, reason: 'icon rail at expanded');
          expect(extended, findsNothing);
        } else {
          expect(rail, findsNothing, reason: 'bottom pill below 900');
        }
        expect(
          probe.width,
          width - _expectedRailWidth(width),
          reason:
              'content fills the window minus the rail; the old '
              'assertion capped it at 720/960, which encoded the removed '
              'global clamp',
        );
      });
    }
  });

  group('content is not clamped', () {
    for (final size in const [
      Size(768, 1024),
      Size(1366, 768),
      Size(1440, 900),
      Size(1920, 1080),
      Size(2560, 1440),
    ]) {
      testWidgets('fills ${size.width.toInt()}px minus the rail', (
        tester,
      ) async {
        await _pump(tester, size);
        expect(tester.takeException(), isNull);
        final probeWidth = tester.getSize(find.byKey(_probe)).width;
        expect(probeWidth, size.width - _expectedRailWidth(size.width));
        // Explicitly not the removed 720 (tablet) / 960 (desktop) caps.
        if (size.width == 768) expect(probeWidth, 768);
        if (size.width >= 1366) expect(probeWidth, greaterThan(960));
      });
    }
  });

  group('phones keep the floating pill at full width', () {
    for (final size in const [Size(320, 640), Size(375, 812)]) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        await _pump(tester, size);
        expect(tester.takeException(), isNull);
        expect(find.byKey(_rail), findsNothing);
        expect(tester.getSize(find.byKey(_probe)).width, size.width);
        expect(find.text('Discover'), findsOneWidget);
        // The unread-count announcement is unchanged.
        expect(
          find.bySemanticsLabel(RegExp('Inbox, 3 unread messages')),
          findsOneWidget,
        );
      });
    }
  });

  group('navigation switches tabs', () {
    testWidgets('extended rail', (tester) async {
      final router = await _pump(tester, const Size(1440, 900));
      expect(find.byKey(_extendedRail), findsOneWidget);
      await tester.tap(find.text('Premium'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_path(router), '/d');
    });

    testWidgets('icon rail at expanded width', (tester) async {
      final router = await _pump(tester, const Size(1024, 768));
      expect(find.byKey(_rail), findsOneWidget);
      expect(find.byKey(_extendedRail), findsNothing);
      await tester.tap(find.text('Premium'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_path(router), '/d');
    });

    testWidgets('bottom pill below 900', (tester) async {
      final router = await _pump(tester, const Size(600, 800));
      await tester.tap(find.text('Matches'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_path(router), '/b');
    });
  });

  testWidgets('extended rail ellipsizes long Tamil labels without overflow', (
    tester,
  ) async {
    await _pump(tester, const Size(1200, 800), locale: const Locale('ta'));
    expectNoOverflowIn(drainExceptions(tester));
    expect(find.byKey(_extendedRail), findsOneWidget);
    expect(find.text('பொருத்தங்கள்'), findsOneWidget);
  });

  testWidgets('rail and page remain usable on a short window', (tester) async {
    await _pump(tester, kShortDesktop);
    expect(find.byKey(_rail), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Every item stays reachable: the rail scrolls instead of overflowing.
    expect(find.text('Premium'), findsOneWidget);
  });

  testWidgets('repeated resizes across every boundary leave a valid layout', (
    tester,
  ) async {
    await _pump(tester, const Size(360, 800));
    for (final width in [...kBoundaryWidths, ...kBoundaryWidths.reversed]) {
      expectNoOverflowIn(await resizeTo(tester, Size(width, 800)));
      expect(
        tester.getSize(find.byKey(_probe)).width,
        width - _expectedRailWidth(width),
        reason: 'after resizing to ${width.toInt()}px',
      );
    }
  });
}
