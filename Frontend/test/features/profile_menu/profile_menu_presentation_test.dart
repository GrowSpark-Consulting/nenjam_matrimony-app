import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile_menu/presentation/pages/profile_menu_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The profile menu is a FULL-SCREEN page, not a partial-width drawer.
///
/// These tests pin the structural contract that change bought: an opaque
/// route on the root navigator, so the page underneath (Discover, plus the
/// bottom-nav pill that belongs to its shell) is not merely covered but taken
/// off stage entirely — and the platform back affordance pops back to it.
///
/// Layout at every shipped phone size is covered separately, by
/// `responsive_pages_audit_test.dart`'s "Profile menu" case.
void main() {
  /// A stand-in for the bottom-nav shell: a page with its own body text and
  /// its own `bottomNavigationBar`, pushing the menu the way Discover's
  /// avatar does.
  Widget host() => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProfileMenuPage(),
                ),
              ),
              child: const Text('DISCOVER'),
            ),
          ),
          bottomNavigationBar: const Text('BOTTOM NAV'),
        ),
      ),
    ),
  );

  /// The menu's providers reach for `GET /profiles/draft`, which no test
  /// harness serves; the identity block settles into its error placeholder.
  /// Every structural expectation below is about the route, not that block.
  Future<void> openMenu(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('DISCOVER'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('covers the page it was opened from, bottom nav included', (
    tester,
  ) async {
    await openMenu(tester);

    expect(find.byType(ProfileMenuPage), findsOneWidget);
    // Off stage, not just overpainted: an opaque route means the Overlay
    // stops building everything beneath it. Nothing of the previous screen
    // shows beside or behind the menu.
    expect(find.text('DISCOVER'), findsNothing);
    expect(find.text('BOTTOM NAV'), findsNothing);
    // And the menu brings no second bottom bar of its own.
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
      isNull,
    );
  });

  testWidgets('back returns to the previous screen', (tester) async {
    await openMenu(tester);

    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileMenuPage), findsNothing);
    expect(find.text('DISCOVER'), findsOneWidget);
    expect(find.text('BOTTOM NAV'), findsOneWidget);
  });
}
