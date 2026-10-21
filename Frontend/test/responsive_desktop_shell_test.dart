import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/theme/app_theme.dart';
import 'package:nenjam_matrimony/core/widgets/layout/responsive_layout.dart';
import 'package:nenjam_matrimony/core/widgets/navigation/app_bottom_nav.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The app frame and the navigation shell at every target viewport: phones
/// keep the bottom pill and the full width; tablets are bounded; desktops get
/// the left rail and a centered column, with no layout exception at any size.
const _sizes = <Size>[
  Size(320, 640),
  Size(375, 812),
  Size(768, 1024),
  Size(1024, 768),
  Size(1366, 768),
  Size(1440, 900),
  Size(1920, 1080),
];

const _probe = ValueKey('probe');

Future<void> _pump(WidgetTester tester, Size size) async {
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
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            NmAppFrame(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in _sizes) {
    testWidgets('app shell lays out cleanly at ${size.width}x${size.height}', (
      tester,
    ) async {
      await _pump(tester, size);
      expect(tester.takeException(), isNull);

      final rail = find.byKey(const ValueKey('desktop-nav-rail'));
      final probe = tester.getSize(find.byKey(_probe));

      if (size.width >= 1024) {
        expect(rail, findsOneWidget);
        // Whole frame is 1056 wide (960 content + 96 rail), centered.
        expect(probe.width, lessThanOrEqualTo(960));
        expect(probe.width, size.width >= 1056 ? 960 : size.width - 96);
      } else {
        expect(rail, findsNothing);
        expect(probe.width, size.width >= 600 ? 720 : size.width);
      }
    });
  }

  testWidgets('desktop rail switches tabs', (tester) async {
    await _pump(tester, const Size(1440, 900));
    await tester.tap(find.text('Premium'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
