import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/profile_menu/presentation/pages/profile_menu_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Content-width contract for the profile menu, from a 320dp phone to a
/// 1920dp desktop window.
///
/// The page used to stretch every section across the whole window: on a
/// desktop the strength card, the menu rows and the premium strip each ran
/// edge to edge, and the rows didn't even share the card's edges. These
/// tests pin the fix — one centred column, capped at
/// [ProfileMenuPage.contentMaxWidth], that every section shares.
///
/// Phone-only sizing and the strength-bar fill are covered by
/// `profile_menu_layout_test.dart`.

const _viewports = <String, Size>{
  'small mobile': Size(320, 568),
  'standard mobile': Size(390, 844),
  'large mobile': Size(430, 932),
  'landscape phone': Size(568, 320),
  'tablet portrait': Size(768, 1024),
  'tablet landscape': Size(1024, 768),
  'desktop': Size(1366, 768),
  'large desktop': Size(1920, 1080),
};

Map<String, dynamic> _draft() => <String, dynamic>{
  'completionPercentage': 72,
  'completionBreakdown': const <Map<String, dynamic>>[],
  'basicDetails': <String, dynamic>{
    'firstName': 'Dhatri',
    'lastName': 'Patel',
    'gender': 'FEMALE',
    'dob': '1999-04-12T00:00:00.000',
  },
  'religionDetails': <String, dynamic>{'community': 'Patidar Community'},
  'locationDetails': <String, dynamic>{
    'city': 'Bengaluru',
    'state': 'Karnataka',
    'country': 'India',
  },
};

/// Pumps the menu at [size]. With [pushed], it is opened over a host page so
/// the AppBar shows its back button, the way the router presents it.
Future<void> _pumpMenu(
  WidgetTester tester,
  Size size, {
  bool pushed = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileDraftResponseProvider.overrideWith((ref) async => _draft()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: pushed
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileMenuPage(),
                      ),
                    ),
                    child: const Text('OPEN'),
                  ),
                ),
              )
            : const ProfileMenuPage(),
      ),
    ),
  );
  if (pushed) await tester.tap(find.text('OPEN'));
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The painted box of a section — its decoration, not the padding or margin
/// around it.
Rect _strengthCard(WidgetTester tester) => tester.getRect(
  find
      .ancestor(
        of: find.text('Profile Strength'),
        matching: find.byType(DecoratedBox),
      )
      .first,
);

Rect _row(WidgetTester tester, String label) => tester.getRect(
  find
      .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
      .first,
);

Rect _premiumStrip(WidgetTester tester) => tester.getRect(
  find.ancestor(of: find.text('Nenjam Premium'), matching: find.byType(Ink)),
);

List<String> _layoutErrors(WidgetTester tester) {
  final out = <String>[];
  while (out.length < 20) {
    final Object? e = tester.takeException() as Object?;
    if (e == null) break;
    out.add(e.toString().split('\n').first);
  }
  return out;
}

void main() {
  for (final entry in _viewports.entries) {
    final name = entry.key;
    final size = entry.value;
    final label = '$name ${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('$label: no overflow, sections share one column', (
      tester,
    ) async {
      await _pumpMenu(tester, size);
      expect(_layoutErrors(tester), isEmpty);

      final card = _strengthCard(tester);
      final myProfile = _row(tester, 'My Profile');
      final editProfile = _row(tester, 'Edit Profile');
      final premium = _premiumStrip(tester);

      // Every section on the same left and right edges.
      for (final other in [myProfile, editProfile, premium]) {
        expect(other.left, moreOrLessEquals(card.left), reason: 'left edge');
        expect(other.right, moreOrLessEquals(card.right), reason: 'right');
      }

      // Never wider than the cap, and centred in the page.
      expect(card.width, lessThanOrEqualTo(ProfileMenuPage.contentMaxWidth));
      expect(
        card.center.dx,
        moreOrLessEquals(size.width / 2),
        reason: 'the column is centred',
      );
      // Nothing escapes the viewport.
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(size.width));
      expect(premium.right, lessThanOrEqualTo(size.width));
    });
  }

  testWidgets('phones use nearly the full width with a 16dp gutter', (
    tester,
  ) async {
    for (final w in const [320.0, 390.0, 430.0]) {
      await _pumpMenu(tester, Size(w, 900));
      final card = _strengthCard(tester);
      expect(card.left, 16, reason: '${w}dp');
      expect(card.width, w - 32, reason: '${w}dp');
    }
  });

  testWidgets('tablets fill the available width with a wider gutter', (
    tester,
  ) async {
    await _pumpMenu(tester, const Size(768, 1024));
    final card = _strengthCard(tester);
    expect(card.left, 24);
    expect(card.width, 768 - 48);
  });

  testWidgets('desktop caps and centres the content column', (tester) async {
    for (final w in const [1366.0, 1920.0]) {
      await _pumpMenu(tester, Size(w, 900));
      final card = _strengthCard(tester);
      final side = (w - ProfileMenuPage.contentMaxWidth) / 2;
      // 960dp column, 32dp gutter either side of the card.
      expect(card.width, ProfileMenuPage.contentMaxWidth - 64, reason: '$w');
      expect(card.left, side + 32, reason: '$w');
      // The hairline under the header uses the same gutter, not a fixed 16.
      final divider = find.byType(Divider).first;
      expect(tester.widget<Divider>(divider).indent, 32, reason: '$w');
      expect(tester.getRect(divider).width, ProfileMenuPage.contentMaxWidth);
    }
  });

  testWidgets('the back button stays over the column on desktop', (
    tester,
  ) async {
    await _pumpMenu(tester, const Size(1920, 1080), pushed: true);

    final card = _strengthCard(tester);
    final back = tester.getRect(find.byType(BackButton));
    // Pulled in from the window edge to sit over the column's left edge…
    expect(back.left, greaterThan(card.left - 48));
    expect(back.left, lessThan(card.left));
    // …and still pops.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileMenuPage), findsNothing);
  });

  testWidgets('the back button is unchanged on a phone', (tester) async {
    await _pumpMenu(tester, const Size(390, 844), pushed: true);

    // AppBar's default leading slot: the 48dp button centred in 56dp.
    expect(tester.getRect(find.byType(BackButton)).left, 4);
  });

  testWidgets('short viewports scroll to the last menu row', (tester) async {
    await _pumpMenu(tester, const Size(568, 320));

    await tester.scrollUntilVisible(
      find.text('Logout'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Logout').hitTestable(), findsOneWidget);
    // The pinned footer stays readable throughout.
    expect(find.text('Terms & Conditions'), findsOneWidget);
    expect(_layoutErrors(tester), isEmpty);
  });
}
