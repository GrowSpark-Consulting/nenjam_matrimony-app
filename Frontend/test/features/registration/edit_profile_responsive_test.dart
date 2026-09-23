import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/edit_profile_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'edit_profile_test_support.dart';

/// Edit Profile's section cards with a realistically *long* profile: every
/// value is the kind that wraps — long names, a long college, a long company,
/// long place names, a long About Me — laid out at the narrowest supported
/// phone, in Tamil (the longer labels of the two locales) and English, at a
/// raised text scale, portrait and landscape.
///
/// The 120dp label column is the risk: a label or value that cannot wrap
/// inside its share of a 320dp card overflows the row. Any RenderFlex
/// overflow is reported as a FlutterError, which fails the test.
void main() {
  const longText =
      'Sri Venkateswara College of Engineering and Technology (Autonomous)';

  ProfileDraft longProfile() => ProfileDraft(
    basicDetails: BasicDetails(
      firstName: 'Venkatalakshmi Subramaniam',
      lastName: 'Ramachandran-Krishnamoorthy',
      gender: 'Female',
      dob: DateTime(1994, 11, 30),
      maritalStatus: 'Awaiting Divorce',
      profileCreatedFor: 'Daughter',
    ),
    religionDetails: const ReligionDetails(
      religion: 'Hindu',
      community: 'Vishwakarma (Kammalar / Asari)',
      subCaste: 'Thiruvannamalai Kammalar Aasari Sub-community',
    ),
    locationDetails: const LocationDetails(
      country: 'United Kingdom of Great Britain and Northern Ireland',
      state: 'Andaman and Nicobar Islands Union Territory',
      city: 'Thiruvananthapuram Municipal Corporation Area',
    ),
    educationDetails: const EducationDetails(
      qualification: 'M.Tech - Master of Technology (Integrated)',
      college: longText,
      occupation: 'Senior Principal Software Development Engineer',
      company: 'Tata Consultancy Services International Private Limited',
      employmentType: 'Self-Employed',
      annualIncome: 'INR 50 Lakhs - 1 Crore per annum',
    ),
    physicalDetails: const PhysicalDetails(height: "5'11\" (180 cm)"),
    lifestyleDetails: LifestyleDetails(
      eatingHabit: 'Eggetarian (Vegetarian with eggs)',
      aboutMe: List.filled(
        12,
        'I love Carnatic music and long walks.',
      ).join(' '),
    ),
  );

  Future<void> pumpAt(
    WidgetTester tester, {
    required Size size,
    required Locale locale,
    double textScale = 1.0,
  }) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;

    final container = ProviderContainer(
      overrides: [
        photoRepositoryProvider.overrideWithValue(EmptyPhotoRepository()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(registrationProvider.notifier)
        .restore(longProfile(), ProfileFlowMode.edit);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
          home: const EditProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls the whole list through the viewport so every card is built and
  /// laid out, not only the first screenful.
  Future<void> scrollThroughAllCards(WidgetTester tester) async {
    for (final section in EditProfileSection.all) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('edit-profile-section-${section.id}')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      // The long values are shown in full (wrapped), not dropped.
      if (section.id == 'education') {
        expect(find.text(longText), findsOneWidget);
      }
    }
  }

  final configs = <(String, Size, Locale, double)>[
    ('320x640 Tamil', const Size(320, 640), const Locale('ta'), 1.0),
    ('320x640 Tamil, text x1.3', const Size(320, 640), const Locale('ta'), 1.3),
    (
      '320x640 English, text x1.3',
      const Size(320, 640),
      const Locale('en'),
      1.3,
    ),
    ('640x320 landscape Tamil', const Size(640, 320), const Locale('ta'), 1.0),
    ('390x844 Tamil', const Size(390, 844), const Locale('ta'), 1.0),
  ];

  for (final (name, size, locale, scale) in configs) {
    testWidgets('long values lay out without overflow — $name', (tester) async {
      await pumpAt(tester, size: size, locale: locale, textScale: scale);
      await scrollThroughAllCards(tester);

      expect(tester.takeException(), isNull);
    });
  }
}
