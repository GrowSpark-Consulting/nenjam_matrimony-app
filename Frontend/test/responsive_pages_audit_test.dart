// Full breakpoint x locale x keyboard matrix across every audited page —
// the single heaviest file in the suite. Runs on main/pre-merge, not PRs.
// See .github/workflows/ci.yml for the fast/full split.
@Tags(['heavy'])
library;

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
import 'package:nenjam_matrimony/features/registration/presentation/pages/create_profile_for_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_about_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_contact_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_education_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_income_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_marital_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_photos_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_name_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_religion_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_basics_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_edit_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/registration_page.dart';
import 'package:nenjam_matrimony/features/profile_photos/data/repositories/photo_repository.dart';
import 'package:nenjam_matrimony/features/profile_photos/domain/models/user_photo.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';
import 'package:nenjam_matrimony/features/settings/presentation/pages/settings_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
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

/// A signed-out auth service. The onboarding contact page reads the current
/// user in `initState`; without this the audit would fail on "No Firebase App
/// has been created", which is a harness gap, not a layout defect.
class _SignedOutAuthService implements FirebaseAuthService {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A photo store with nothing in it — the empty state the Add Photos step
/// opens on. Without it the audit would need a live API client and a
/// Firebase token, neither of which says anything about layout.
class _EmptyPhotoRepository implements PhotoRepository {
  @override
  Future<List<UserPhoto>> fetchPhotos() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  List<Override> overrides = const [],
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
      overrides: overrides,
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
  List<Override> overrides = const [],
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

      for (final e in await _pumpAt(
        tester,
        build(),
        size,
        locale,
        overrides: overrides,
      )) {
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
        for (final e in await _pumpAt(
          tester,
          build(),
          size,
          locale,
          keyboard: inset,
          overrides: overrides,
        )) {
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

  testWidgets('Profile For is responsive across phone sizes', (tester) async {
    // Seven wrapping pills plus a notice and a pinned CTA — the run that is
    // most likely to overflow is the shortest landscape phone in Tamil,
    // whose labels are the longest of the two locales.
    await _audit(
      tester,
      'CreateProfileForPage',
      () => const CreateProfileForPage(),
    );
  });

  testWidgets('Onboarding name is responsive across phone sizes', (
    tester,
  ) async {
    // Two full-width text fields, a second headline, and a row of three
    // narrow date boxes — the row is the part at risk, because it is the one
    // place onboarding puts fields side by side. Audited with the keyboard
    // raised, since typing a date is what the screen is for.
    await _audit(
      tester,
      'OnboardingNamePage',
      () => const OnboardingNamePage(),
      keyboard: true,
    );
  });

  testWidgets('Onboarding religion is responsive across phone sizes', (
    tester,
  ) async {
    // Three dropdowns, one with a help affordance beside it, plus a
    // two-line checkbox label and a pinned CTA.
    await _audit(
      tester,
      'OnboardingReligionPage',
      () => const OnboardingReligionPage(),
    );
  });

  testWidgets('Onboarding contact is responsive across phone sizes', (
    tester,
  ) async {
    // Two text fields (one with an inline country picker), a wrapping
    // headline and a legal line under the CTA — audited with the keyboard
    // up, since both fields raise one.
    await _audit(
      tester,
      'OnboardingContactPage',
      () => const OnboardingContactPage(),
      keyboard: true,
      overrides: [
        firebaseAuthServiceProvider.overrideWithValue(_SignedOutAuthService()),
      ],
    );
  });

  testWidgets('Onboarding marital is responsive across phone sizes', (
    tester,
  ) async {
    await _audit(
      tester,
      'OnboardingMaritalPage',
      () => const OnboardingMaritalPage(),
    );
  });

  testWidgets('Onboarding education is responsive across phone sizes', (
    tester,
  ) async {
    // A dropdown and a free-text college field, so the keyboard matters.
    await _audit(
      tester,
      'OnboardingEducationPage',
      () => const OnboardingEducationPage(),
      keyboard: true,
    );
  });

  testWidgets('Onboarding income is responsive across phone sizes', (
    tester,
  ) async {
    // The densest step: four fields, a help affordance and a longer CTA.
    await _audit(
      tester,
      'OnboardingIncomePage',
      () => const OnboardingIncomePage(),
      keyboard: true,
    );
  });

  testWidgets('Onboarding photos is responsive across phone sizes', (
    tester,
  ) async {
    await _audit(
      tester,
      'OnboardingPhotosPage',
      () => const OnboardingPhotosPage(),
      overrides: [
        photoRepositoryProvider.overrideWithValue(_EmptyPhotoRepository()),
      ],
    );
  });

  testWidgets('Onboarding about is responsive across phone sizes', (
    tester,
  ) async {
    // A multi-line text area with a counter — the one step whose content
    // grows as the member types.
    await _audit(
      tester,
      'OnboardingAboutPage',
      () => const OnboardingAboutPage(),
      keyboard: true,
    );
  });

  testWidgets('Profile basics is responsive across phone sizes', (tester) async {
    // A gender chip row, two dropdowns, a sub-community text field and a
    // pinned CTA — the run most likely to overflow is the shortest landscape
    // phone in Tamil, whose labels are the longest of the two locales.
    await _audit(tester, 'ProfileBasicsPage', () => const ProfileBasicsPage());
  });

  testWidgets('Profile edit is responsive across phone sizes', (tester) async {
    // Edit Profile's single editable page: every field section stacked in
    // one viewport. The longest page in the app, and the one most exposed to
    // a raised keyboard.
    await _audit(
      tester,
      'ProfileEditPage',
      () => const ProfileEditPage(),
      overrides: [
        photoRepositoryProvider.overrideWithValue(_EmptyPhotoRepository()),
      ],
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
