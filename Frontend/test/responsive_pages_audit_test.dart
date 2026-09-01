import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/compatibility_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/presentation/pages/discover_page.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/pages/inbox_page.dart';
import 'package:nenjam_matrimony/features/matches/presentation/pages/matches_page.dart';
import 'package:nenjam_matrimony/features/premium/presentation/pages/premium_page.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/pages/profile_detail_page.dart';
import 'package:nenjam_matrimony/features/profile_menu/presentation/pages/profile_menu_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_wizard_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/registration_page.dart';
import 'package:nenjam_matrimony/features/settings/presentation/pages/settings_page.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pre-release responsive audit for whole screens.
///
/// `responsive_audit_test.dart` covers individual Profile cards in
/// isolation; this file drives the real pages, at the phone widths the app
/// actually ships to, in both orientations, with a notch-sized safe area and
/// (for pages with text fields) an on-screen keyboard.
const _portrait = <Size>[
  Size(320, 568), // smallest supported phone
  Size(360, 640),
  Size(375, 812),
  Size(393, 873),
  Size(412, 915),
  Size(480, 960),
];

List<Size> _allSizes() => [
      ..._portrait,
      // Landscape: same devices rotated.
      ..._portrait.map((s) => Size(s.height, s.width)),
    ];

DiscoveryProfileEntity _profile() => const DiscoveryProfileEntity(
      id: 'audit-1',
      matrimonyId: 'NM123456',
      name: 'Diagnostic Tester With A Fairly Long Name',
      age: 29,
      location: 'Chennai, Tamil Nadu, India',
      profession: 'Senior Software Engineer',
      education: 'M.Tech, Computer Science',
      photoUrls: [],
      isVerified: true,
      isPremium: true,
      isPsychologyCompleted: true,
      isOnline: true,
      horoscopeAvailable: true,
      photoProtected: false,
      phoneVerified: true,
      compatibility: CompatibilityEntity(
        aiMatchPercent: 88,
        astroMatchPercent: 76,
        psychologyMatchPercent: 81,
        overallCompatibility: 85,
        lifestyleMatchPercent: 90,
        familyMatchPercent: 82,
        educationMatchPercent: 95,
        valuesMatchPercent: 88,
        goalsMatchPercent: 80,
      ),
      tags: [],
      religion: 'Hindu',
      caste: 'Iyer',
      community: 'Tamil',
      height: "5'9\"",
      diet: 'Vegetarian',
      distanceKm: 12.4,
      gender: 'Female',
      profileComplete: true,
      maritalStatus: 'Never Married',
      motherTongue: 'Tamil',
      smoking: 'No',
      drinking: 'No',
      physicalStatus: 'Normal',
      company: 'Big Tech Corp',
      annualIncome: '25-30 Lakhs',
      bio: 'Loves travel and books.',
      languages: ['Tamil', 'English', 'Hindi'],
      hobbies: ['Reading', 'Travel'],
    );

/// Drains every layout error recorded for the frame, not just the first —
/// one screen can overflow in several places at once.
List<Object> _drain(WidgetTester tester) {
  final out = <Object>[];
  while (true) {
    final Object? e = tester.takeException() as Object?;
    if (e == null) break;
    out.add(e);
    if (out.length > 20) break;
  }
  return out;
}

/// Keeps enough of the error to identify *which* widget overflowed — the
/// first line alone is just "A RenderFlex overflowed by N pixels".
String _short(Object e) {
  final lines = e
      .toString()
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .take(6)
      .toList();
  return lines.join(' | ');
}

Future<List<Object>> _pumpAt(
  WidgetTester tester,
  Widget page,
  Size size,
  Locale locale, {
  double keyboard = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  // Notch + home-indicator sized safe area, so SafeArea handling is
  // genuinely exercised rather than assumed.
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  await tester.binding.setSurfaceSize(size);

  // Tear the tree down between configurations. Flutter reports a given
  // RenderFlex overflow only ONCE per render object, and pumpWidget reuses
  // render objects across calls — without this, only the first size in the
  // sweep ever reports and every later width looks clean.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    ),
  );

  // Several screens hold repeating animations (shimmer, pulsing dots), so
  // pumpAndSettle would never return. A bounded walk covers the mock
  // repositories' load delays instead.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return _drain(tester);
}

Future<void> _audit(
  WidgetTester tester,
  String name,
  Widget Function() build, {
  bool keyboard = false,
  List<Locale> locales = const [Locale('en'), Locale('ta')],
}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final failures = <String>[];
  for (final locale in locales) {
    for (final size in _allSizes()) {
      final tag = '${size.width.toInt()}x${size.height.toInt()} '
          '${size.width > size.height ? 'landscape' : 'portrait'} '
          '[${locale.languageCode}]';

      for (final e in await _pumpAt(tester, build(), size, locale)) {
        final line = '$name @ $tag -> ${_short(e)}';
        debugPrint('RESPFAIL $line');
        failures.add(line);
      }

      if (keyboard) {
        // Proportional, not a flat 300dp: a soft keyboard takes roughly
        // 45% of the viewport height, so a flat value would model a
        // landscape phone as having ~15dp of usable space — a scenario no
        // real device produces.
        final inset = (size.height * 0.45).roundToDouble();
        for (final e
            in await _pumpAt(tester, build(), size, locale, keyboard: inset)) {
          final line = '$name @ $tag +keyboard -> ${_short(e)}';
          debugPrint('RESPFAIL $line');
          failures.add(line);
        }
      }
    }
  }

  expect(
    failures,
    isEmpty,
    reason: '\n--- ${failures.length} layout failure(s) ---\n'
        '${failures.join('\n')}\n',
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // SettingsPage reads the global StorageService, whose `late _prefs` throws
    // a LateInitializationError until init() has run. That is a harness gap,
    // not a layout defect.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await storageService.init();
  });

  testWidgets('Discover is responsive across phone sizes', (tester) async {
    await _audit(tester, 'DiscoverPage', () => const DiscoverPage());
  });

  testWidgets('Matches is responsive across phone sizes', (tester) async {
    await _audit(tester, 'MatchesPage', () => const MatchesPage());
  });

  testWidgets('Profile Detail is responsive across phone sizes', (tester) async {
    await _audit(
      tester,
      'ProfileDetailPage',
      () => ProfileDetailPage(profile: _profile()),
    );
  });

  testWidgets('Registration is responsive across phone sizes', (tester) async {
    await _audit(
      tester,
      'RegistrationPage',
      () => const RegistrationPage(),
      keyboard: true,
    );
  });

  testWidgets('Profile wizard is responsive across phone sizes', (tester) async {
    await _audit(
      tester,
      'ProfileWizardPage',
      () => const ProfileWizardPage(),
      keyboard: true,
    );
  });

  testWidgets('Inbox is responsive across phone sizes', (tester) async {
    await _audit(tester, 'InboxPage', () => const InboxPage());
  });

  testWidgets('Profile menu is responsive across phone sizes', (tester) async {
    await _audit(tester, 'ProfileMenuPage', () => const ProfileMenuPage());
  });

  testWidgets('Premium is responsive across phone sizes', (tester) async {
    await _audit(tester, 'PremiumPage', () => const PremiumPage());
  });

  testWidgets('Settings is responsive across phone sizes', (tester) async {
    await _audit(tester, 'SettingsPage', () => const SettingsPage());
  });
}
