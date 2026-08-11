import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nenjam_matrimony/core/providers/locale_provider.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/core/widgets/buttons/gradient_button.dart';
import 'package:nenjam_matrimony/features/language/presentation/pages/language_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Language selection must switch the app locale without ever ejecting a
/// signed-in member into onboarding.
///
/// The page serves two entry points that look identical on screen but must
/// behave differently, which is what the original bug got wrong:
///
///   * pushed from the drawer / Settings — already inside the app
///   * the onboarding root — reached with `go`, nothing to pop
void main() {
  // StorageService holds `late final _prefs`, so init() can only run once per
  // test process — hence setUpAll, with each test resetting the value it
  // cares about through the service rather than re-initialising.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });

  setUp(() async {
    await storageService.setLanguage('en');
  });

  group('opened from inside the app (drawer / Settings)', () {
    testWidgets('selecting Tamil switches the locale and stays put',
        (tester) async {
      final h = await _pump(tester, fromInsideApp: true);

      expect(h.locale().languageCode, 'en');

      await tester.tap(find.text('தமிழ்'));
      await tester.pumpAndSettle();

      expect(h.locale().languageCode, 'ta');
      expect(h.location, RouteNames.language,
          reason: 'picking a language must not navigate anywhere');
      expect(find.byType(LanguagePage), findsOneWidget);
    });

    testWidgets('Tamil back to English switches again', (tester) async {
      final h = await _pump(tester, fromInsideApp: true);

      await tester.tap(find.text('தமிழ்'));
      await tester.pumpAndSettle();
      expect(h.locale().languageCode, 'ta');

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(h.locale().languageCode, 'en');
      expect(h.location, RouteNames.language);
    });

    testWidgets('the confirm button returns to the previous screen, never '
        'onboarding', (tester) async {
      final h = await _pump(tester, fromInsideApp: true);

      await tester.tap(find.text('தமிழ்'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NmGradientButton));
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.discover);
      expect(h.location, isNot(RouteNames.onboarding));
      expect(h.locale().languageCode, 'ta',
          reason: 'the choice must survive leaving the screen');
    });

    testWidgets('Android back returns to the previous screen', (tester) async {
      final h = await _pump(tester, fromInsideApp: true);

      await tester.tap(find.text('தமிழ்'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.discover);
      expect(h.locale().languageCode, 'ta');
    });
  });

  group('opened as the onboarding root', () {
    testWidgets('the confirm button still advances to onboarding',
        (tester) async {
      final h = await _pump(tester, fromInsideApp: false);

      await tester.tap(find.byType(NmGradientButton));
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.onboarding);
    });
  });

  group('persistence', () {
    testWidgets('the chosen language is written to storage', (tester) async {
      final h = await _pump(tester, fromInsideApp: true);

      await tester.tap(find.text('தமிழ்'));
      await tester.pumpAndSettle();

      expect(storageService.selectedLanguage, 'ta');
      expect(h.locale().languageCode, 'ta');
    });

    testWidgets('a restart restores the saved language', (tester) async {
      // Simulates the next cold start: storage already holds 'ta', and a
      // brand-new container seeds LocaleNotifier.build() from it — which is
      // exactly what happens when the app process is recreated.
      await storageService.setLanguage('ta');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(localeProvider).languageCode, 'ta');
    });
  });
}

class _Harness {
  _Harness(this.router, this.container);

  final GoRouter router;
  final ProviderContainer container;

  String get location => router.state.matchedLocation;
  Locale locale() => container.read(localeProvider);
}

/// Pumps the real [LanguagePage].
///
/// [fromInsideApp] chooses the entry point: `true` pushes it over Discover
/// (so `context.canPop()` is true, as from the drawer), `false` makes it the
/// initial route (as on first launch).
Future<_Harness> _pump(
  WidgetTester tester, {
  required bool fromInsideApp,
}) async {
  GoRoute stub(String path) => GoRoute(
        path: path,
        builder: (_, __) => Scaffold(body: Text('stub $path')),
      );

  final router = GoRouter(
    initialLocation:
        fromInsideApp ? RouteNames.discover : RouteNames.language,
    routes: [
      stub(RouteNames.discover),
      stub(RouteNames.onboarding),
      GoRoute(
        path: RouteNames.language,
        builder: (_, __) => const LanguagePage(),
      ),
    ],
  );

  final container = ProviderContainer();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          locale: ref.watch(localeProvider),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  if (fromInsideApp) {
    router.push(RouteNames.language);
    await tester.pumpAndSettle();
  }

  return _Harness(router, container);
}
