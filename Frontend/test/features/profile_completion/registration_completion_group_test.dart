import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/profile_completion/domain/profile_completion_aggregator.dart';
import 'package:nenjam_matrimony/features/profile_completion/presentation/pages/profile_completion_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The Registration information group, and the four-module breakdown behind
/// it.
///
/// The backend now scores four slices — registration 60, family 10, horoscope
/// 5, verification 25 — and reports the registration slice field by field so
/// the screen can name what is missing rather than saying only "incomplete".
/// The rule these pin is that a member who has just finished signing up is
/// never asked again for what they already gave.
void main() {
  Map<String, dynamic> module(
    String id,
    double weight,
    bool isComplete,
    int wizardStep,
  ) => <String, dynamic>{
    'id': id,
    'weight': weight,
    'isComplete': isComplete,
    'wizardStep': wizardStep,
  };

  Map<String, dynamic> field(
    String id,
    bool isComplete, {
    int wizardStep = 0,
    String section = 'basicDetails',
    bool optional = false,
  }) => <String, dynamic>{
    'id': id,
    'section': section,
    'wizardStep': wizardStep,
    'isComplete': isComplete,
    'optional': optional,
  };

  /// Every registration item answered — the newly registered member.
  List<Map<String, dynamic>> allAnswered() => [
        for (final id in const [
          'profileCreatedFor', 'gender', 'firstName', 'lastName', 'dob',
          'religion', 'community', 'country', 'state', 'city',
          'maritalStatus', 'height', 'diet', 'qualification', 'college',
          'annualIncome', 'employmentType', 'workIndustry', 'occupation',
          'company',
        ])
          field(id, true),
        field('subCommunity', false, optional: true),
        field('photo', true, wizardStep: 11, section: 'photos'),
      ];

  Map<String, dynamic> draft({
    required int percentage,
    List<Map<String, dynamic>> breakdown = const [],
    List<Map<String, dynamic>>? requiredFields,
    bool? registrationComplete,
  }) => <String, dynamic>{
        'completionPercentage': percentage,
        'completionBreakdown': breakdown,
        if (requiredFields != null) 'requiredFields': requiredFields,
        if (registrationComplete != null)
          'registrationComplete': registrationComplete,
      };

  /// The four modules the backend now reports.
  List<Map<String, dynamic>> fourModules({
    bool registration = true,
    bool family = false,
    bool horoscope = false,
    bool verification = false,
  }) => [
        module('registration', 60, registration, 0),
        module('family', 10, family, 7),
        module('horoscope', 5, horoscope, 8),
        module('verification', 25, verification, 12),
      ];

  Future<void> pump(WidgetTester tester, Map<String, dynamic> json) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileDraftResponseProvider.overrideWith((ref) async => json),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProfileCompletionPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ─── A newly registered user ────────────────────────────────────────

  group('a newly registered user', () {
    testWidgets('is never asked for a registration field again', (
      tester,
    ) async {
      await pump(
        tester,
        draft(
          percentage: 65,
          breakdown: fourModules(),
          requiredFields: allAnswered(),
          registrationComplete: true,
        ),
      );

      expect(find.text('65%'), findsOneWidget);
      // The whole group is absent — not an empty header, absent.
      expect(find.text('Registration information'), findsNothing);
      // And none of the individual answers are named.
      for (final label in const [
        'First Name',
        'Date of Birth',
        'Industry',
        'Community',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('is shown the three sections that actually remain', (
      tester,
    ) async {
      await pump(
        tester,
        draft(
          percentage: 65,
          breakdown: fourModules(),
          requiredFields: allAnswered(),
          registrationComplete: true,
        ),
      );

      // Family and horoscope are cards; verification is deliberately filtered
      // off this screen while still counting toward the headline figure.
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Horoscope'), findsOneWidget);
    });

    testWidgets('does not list the optional sub-community as missing', (
      tester,
    ) async {
      await pump(
        tester,
        draft(
          percentage: 65,
          breakdown: fourModules(),
          // subCommunity is unanswered, and optional.
          requiredFields: allAnswered(),
          registrationComplete: true,
        ),
      );

      expect(find.text('Registration information'), findsNothing);
      expect(find.text('Sub Caste'), findsNothing);
    });
  });

  // ─── Photo-less and legacy ──────────────────────────────────────────

  group('an incomplete registration', () {
    testWidgets('names the photo when none has been uploaded', (tester) async {
      final fields = allAnswered()
        ..removeWhere((f) => f['id'] == 'photo')
        ..add(field('photo', false, wizardStep: 11, section: 'photos'));

      await pump(
        tester,
        draft(
          percentage: 62,
          breakdown: fourModules(registration: false),
          requiredFields: fields,
          registrationComplete: false,
        ),
      );

      expect(find.text('Registration information'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);
    });

    testWidgets('names only the fields a legacy profile genuinely lacks', (
      tester,
    ) async {
      final fields = allAnswered()
          .map((f) => const ['height', 'diet', 'workIndustry'].contains(f['id'])
              ? {...f, 'isComplete': false}
              : f)
          .toList();

      await pump(
        tester,
        draft(
          percentage: 51,
          breakdown: fourModules(registration: false),
          requiredFields: fields,
          registrationComplete: false,
        ),
      );

      expect(find.text('Registration information'), findsOneWidget);
      expect(find.text('Height'), findsOneWidget);
      expect(find.text('Industry'), findsOneWidget);
      // Everything it does have stays unmentioned.
      expect(find.text('First Name'), findsNothing);
      expect(find.text('Community'), findsNothing);
    });
  });

  // ─── The remaining sections, one at a time ──────────────────────────

  group('the sections that remain', () {
    testWidgets('missing About Family is offered', (tester) async {
      await pump(
        tester,
        draft(
          percentage: 90,
          breakdown: fourModules(horoscope: true, verification: true),
          requiredFields: allAnswered(),
          registrationComplete: true,
        ),
      );
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Still Growing'), findsOneWidget);
    });

    testWidgets('missing Horoscope is offered', (tester) async {
      await pump(
        tester,
        draft(
          percentage: 95,
          breakdown: fourModules(family: true, verification: true),
          requiredFields: allAnswered(),
          registrationComplete: true,
        ),
      );
      expect(find.text('Horoscope'), findsOneWidget);
    });

    testWidgets('missing Verification still counts in the figure but is not '
        'carded here', (tester) async {
      await pump(
        tester,
        draft(
          percentage: 75,
          breakdown: fourModules(family: true, horoscope: true),
          requiredFields: allAnswered(),
          registrationComplete: true,
        ),
      );

      // The backend figure is shown untouched even though verification —
      // the only thing still missing — has no card on this screen.
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Still Growing'), findsNothing);
    });

    testWidgets('everything done shows nothing left to do', (tester) async {
      await pump(
        tester,
        draft(
          percentage: 100,
          breakdown: fourModules(
            family: true,
            horoscope: true,
            verification: true,
          ),
          requiredFields: allAnswered(),
          registrationComplete: true,
        ),
      );

      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Registration information'), findsNothing);
      expect(find.text('Still Growing'), findsNothing);
    });
  });

  // ─── Old responses ──────────────────────────────────────────────────

  group('a response from an older API', () {
    testWidgets('renders legacy breakdown ids without crashing', (
      tester,
    ) async {
      // The ten-module shape this replaced. Every id below is gone from the
      // backend, and the screen must still render rather than throw.
      await pump(
        tester,
        draft(
          percentage: 42,
          breakdown: [
            module('registration', 20, true, 0),
            module('education', 10, false, 4),
            module('physical', 5, false, 5),
            module('lifestyle', 5, false, 6),
            module('psychology', 3, false, 9),
            module('partnerPreference', 5, false, 10),
            module('photos', 12, false, 11),
            module('family', 10, false, 7),
            module('horoscope', 5, false, 8),
            module('verification', 25, false, 12),
          ],
        ),
      );

      expect(find.text('42%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // No requiredFields in the payload, so the group cannot be rendered —
      // and must not be guessed at.
      expect(find.text('Registration information'), findsNothing);
    });

    testWidgets('an unknown module id renders blank rather than throwing', (
      tester,
    ) async {
      await pump(
        tester,
        draft(
          percentage: 10,
          breakdown: [module('somethingNewer', 7, false, 3)],
        ),
      );
      expect(find.text('10%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ─── The aggregator's own contract ──────────────────────────────────

  group('profileCompletenessFromBackend', () {
    test('reads requiredFields and excludes the optional one', () {
      final result = profileCompletenessFromBackend(
        51,
        const [],
        requiredFieldsJson: [
          field('height', false, wizardStep: 5, section: 'physicalDetails'),
          field('subCommunity', false, optional: true),
          field('firstName', true),
        ],
        registrationComplete: false,
      );

      expect(result.registrationComplete, isFalse);
      expect(result.requiredFields, hasLength(3));
      expect(
        result.missingRequiredFields.map((f) => f.id),
        ['height'],
      );
    });

    test('treats an old response with no requiredFields as nothing to ask', () {
      // Absence must not be read as "everything is missing" — that would make
      // an older server nag for every field it never reported.
      final result = profileCompletenessFromBackend(42, const []);
      expect(result.registrationComplete, isTrue);
      expect(result.missingRequiredFields, isEmpty);
    });

    test('derives registrationComplete when only the fields are sent', () {
      final result = profileCompletenessFromBackend(
        51,
        const [],
        requiredFieldsJson: [field('height', false)],
      );
      expect(result.registrationComplete, isFalse);
    });

    test('tolerates a malformed field entry', () {
      final result = profileCompletenessFromBackend(
        10,
        const [],
        requiredFieldsJson: const [<String, dynamic>{}],
      );
      // Defaults to complete and non-optional rather than throwing.
      expect(result.requiredFields.single.isComplete, isTrue);
      expect(result.registrationComplete, isTrue);
    });

    test('keeps sorting missing modules heaviest first', () {
      final result = profileCompletenessFromBackend(30, [
        module('horoscope', 5, false, 8),
        module('registration', 60, false, 0),
        module('family', 10, false, 7),
      ]);
      expect(
        result.missingModules.map((m) => m.module.id),
        ['registration', 'family', 'horoscope'],
      );
      expect(result.highestImpactModule?.module.id, 'registration');
    });
  });
}
