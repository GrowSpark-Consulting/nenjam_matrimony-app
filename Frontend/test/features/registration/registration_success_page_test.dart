import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile/domain/models/profile.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/registration_success_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Builds a finalized profile. [completionPercentage] is the live figure the
/// page must read; [profileCompletePct] is the stale persisted column it must
/// ignore — they are deliberately different in these tests.
Profile _profile({
  int completionPercentage = 87,
  int profileCompletePct = 42,
  List<ProfilePhotoInfo> photos = const [],
  AstrologyInfo? astrology,
  PartnerPreferenceInfo? partnerPreference,
}) {
  return Profile(
    firstName: 'Arjun',
    lastName: 'Krishnan',
    dob: DateTime(1996, 4, 12),
    gender: 'MALE',
    maritalStatus: 'NEVER_MARRIED',
    religion: 'Hindu',
    caste: 'Iyer',
    motherTongue: 'Tamil',
    heightCm: 175,
    highestEducation: 'M.Tech',
    profession: 'Engineer',
    currentCity: 'Chennai',
    currentState: 'Tamil Nadu',
    isProfileComplete: true,
    profileCompletePct: profileCompletePct,
    photos: photos,
    astrology: astrology,
    partnerPreference: partnerPreference,
    completion: ProfileCompletionInfo(
      percentage: completionPercentage,
      completedSections: const [],
      missingSections: const [],
    ),
  );
}

/// Partner preference carrying the API's defaults; pass a list to mark one
/// as genuinely chosen.
PartnerPreferenceInfo _pref({List<String> preferredReligions = const []}) =>
    PartnerPreferenceInfo(
      minAge: 18,
      maxAge: 45,
      minHeightCm: 140,
      maxHeightCm: 210,
      preferredReligions: preferredReligions,
      preferredCastes: const [],
      minIncomeLakhs: null,
      preferredCities: const [],
      preferredEducation: const [],
      maritalStatusPref: const [],
    );

const _photo = ProfilePhotoInfo(
  id: 'p1',
  cdnUrl: 'https://cdn.example/p1.jpg',
  isPrimary: true,
  order: 0,
  isApproved: true,
);

/// Seeds [registrationProvider] with a specific draft so the local-first
/// path can be exercised.
class _SeededRegistrationNotifier extends RegistrationNotifier {
  _SeededRegistrationNotifier(this._seed);
  final ProfileDraft _seed;

  @override
  ProfileDraft build() => _seed;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RegistrationSuccessPage(),
      ),
    ),
  );
  // Bounded: the page runs entrance animations that never fully settle.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A draft carrying real wizard data, used for the local-first assertions.
ProfileDraft _populatedDraft() => const ProfileDraft().copyWith(
      basicDetails: const BasicDetails(
        firstName: 'Arjun',
        lastName: 'Krishnan',
        gender: 'MALE',
        maritalStatus: 'NEVER_MARRIED',
        profileCreatedFor: 'Self',
      ),
    );

void main() {
  group('backend-sourced values', () {
    testWidgets('renders the live completion percentage, not profileCompletePct',
        (tester) async {
      await _pump(tester, overrides: [
        myProfileProvider.overrideWith((ref) async => _profile(
              completionPercentage: 87,
              profileCompletePct: 42,
            )),
      ]);

      expect(find.text('Profile 87% Complete'), findsOneWidget);
      expect(find.text('Profile 42% Complete'), findsNothing);
      expect(find.text('Profile 100% Complete'), findsNothing);
    });

    testWidgets('photos: Added when the profile has photos', (tester) async {
      await _pump(tester, overrides: [
        myProfileProvider
            .overrideWith((ref) async => _profile(photos: const [_photo])),
      ]);
      expect(find.text('Photos Added'), findsOneWidget);
      expect(find.text('Photos Skipped'), findsNothing);
    });

    testWidgets('photos: Skipped when the profile has none', (tester) async {
      await _pump(tester, overrides: [
        myProfileProvider.overrideWith((ref) async => _profile()),
      ]);
      expect(find.text('Photos Skipped'), findsOneWidget);
      expect(find.text('Photos Added'), findsNothing);
    });

    testWidgets('horoscope: derived from rasi even when the flag is false',
        (tester) async {
      await _pump(tester, overrides: [
        myProfileProvider.overrideWith((ref) async => _profile(
              astrology: const AstrologyInfo(rasi: 'Mesham'),
            )),
      ]);
      expect(find.text('Horoscope Ready'), findsOneWidget);
    });

    testWidgets('horoscope: Skipped when there is no astrology record',
        (tester) async {
      await _pump(tester, overrides: [
        myProfileProvider.overrideWith((ref) async => _profile(astrology: null)),
      ]);
      expect(find.text('Horoscope Skipped'), findsOneWidget);
    });

    testWidgets('partner preference: default-only ranges do not count',
        (tester) async {
      await _pump(tester, overrides: [
        myProfileProvider.overrideWith((ref) async => _profile(
              partnerPreference: _pref(),
            )),
      ]);
      expect(find.text('Partner Preferences Saved'), findsNothing);
    });

    testWidgets('partner preference: a real selection shows the card',
        (tester) async {
      await _pump(tester, overrides: [
        myProfileProvider.overrideWith((ref) async => _profile(
              partnerPreference: _pref(preferredReligions: const ['Hindu']),
            )),
      ]);
      expect(find.text('Partner Preferences Saved'), findsOneWidget);
    });
  });

  group('local-first behaviour', () {
    testWidgets('paints draft values immediately instead of a spinner',
        (tester) async {
      final completer = Completer<Profile>();
      await _pump(tester, overrides: [
        registrationProvider.overrideWith(
          () => _SeededRegistrationNotifier(_populatedDraft()),
        ),
        myProfileProvider.overrideWith((ref) => completer.future),
      ]);

      // Request still in flight: no spinner, draft figures already showing.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('% Complete'), findsOneWidget);

      // Backend answer lands and upgrades the figure in place.
      completer.complete(_profile(completionPercentage: 87));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Profile 87% Complete'), findsOneWidget);
    });

    testWidgets('keeps draft values when the refresh fails', (tester) async {
      await _pump(tester, overrides: [
        registrationProvider.overrideWith(
          () => _SeededRegistrationNotifier(_populatedDraft()),
        ),
        myProfileProvider.overrideWith((ref) async => throw Exception('offline')),
      ]);

      // The user is not punished for a failed background refresh.
      expect(find.textContaining('% Complete'), findsOneWidget);
      expect(find.text('Something went wrong'), findsNothing);
    });
  });

  group('loading and error states', () {
    testWidgets('shows a spinner when there is no draft to fall back on',
        (tester) async {
      // Left deliberately unresolved: completing it here would mount the
      // celebration layout, whose entrance animations leave pending timers
      // at teardown. The transition itself is covered by the local-first
      // test above.
      final completer = Completer<Profile>();
      await _pump(tester, overrides: [
        myProfileProvider.overrideWith((ref) => completer.future),
      ]);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows retry on failure, and still offers a way into the app',
        (tester) async {
      await _pump(tester, overrides: [
        myProfileProvider.overrideWith((ref) async => throw Exception('offline')),
      ]);

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Meet Your First Match'), findsOneWidget);
    });
  });

  group('localization', () {
    testWidgets('renders Tamil copy for the same backend data', (tester) async {
      await _pump(
        tester,
        locale: const Locale('ta'),
        overrides: [
          myProfileProvider.overrideWith((ref) async => _profile(
                completionPercentage: 87,
                photos: const [_photo],
                astrology: const AstrologyInfo(rasi: 'Mesham'),
              )),
        ],
      );

      expect(find.text('சுயவிவரம் 87% முடிந்தது'), findsOneWidget);
      expect(find.text('புகைப்படங்கள் சேர்க்கப்பட்டன'), findsOneWidget);
      expect(find.text('ஜாதகம் தயார்'), findsOneWidget);
    });
  });
}
