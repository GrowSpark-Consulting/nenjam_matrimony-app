import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/constants/profile_options.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/step_basic_info.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/step_education.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/step_location.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/step_religion.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'onboarding_test_support.dart';

/// The Edit Profile steps, as Task 2 reshaped them.
///
/// These are the same widgets the registration wizard builds — the point of
/// the task was that Edit Profile follows the registration flow rather than
/// growing a second one, so there is nothing separate to test. What is new is
/// the dependent dropdowns, the work section, and the rule that an edit must
/// never silently discard a value the curated lists do not carry.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
    // RegistrationHelperTip fades in through flutter_animate, whose ticker
    // outlives the tree if a test ends mid-animation.
    await tester.pump(const Duration(seconds: 1));
  }

  /// Taps the option chip labelled [option].
  ///
  /// OtherOptionField renders its options as ChoiceChips, and every value
  /// used here is unique across the step under test.
  Future<void> choose(WidgetTester tester, String option) async {
    final chip = find.widgetWithText(ChoiceChip, option).first;
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  // ─── Loading existing values ────────────────────────────────────────

  group('opening Edit Profile on a saved profile', () {
    testWidgets('shows the stored basic answers, including Profile for', (
      tester,
    ) async {
      await pump(
        tester,
        StepBasicInfo(
          details: BasicDetails(
            profileCreatedFor: 'Daughter',
            firstName: 'Meera',
            lastName: 'Rajan',
            gender: 'Female',
            maritalStatus: 'Never Married',
            dob: DateTime(1995, 3, 21),
          ),
          onChanged: (_) {},
        ),
      );

      expect(find.text('My Daughter'), findsOneWidget);
      expect(find.text('Meera'), findsOneWidget);
      expect(find.text('Rajan'), findsOneWidget);
      // The Task 1 date field, reused verbatim.
      expect(find.text('21'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);
      expect(find.text('1995'), findsOneWidget);
    });

    testWidgets('shows the stored work answers', (tester) async {
      await pump(
        tester,
        StepEducation(
          details: const EducationDetails(
            qualification: 'B.E / B.Tech',
            college: 'Anna University',
            annualIncome: 'Rs. 10 - 15 Lakhs',
            employmentType: 'Private',
            workIndustry: 'IT / Software',
            occupation: 'Software Engineer',
            company: 'Acme',
          ),
          onChanged: (_) {},
        ),
      );

      expect(find.text('Anna University'), findsOneWidget);
      expect(find.text('Acme'), findsOneWidget);
      expect(find.text('IT / Software'), findsOneWidget);
    });
  });

  // ─── Religion → community ───────────────────────────────────────────

  group('religion drives community', () {
    testWidgets('offers only the chosen religion\'s communities', (
      tester,
    ) async {
      ReligionDetails? emitted;
      await pump(
        tester,
        StepReligion(
          details: const ReligionDetails(religion: 'Hindu'),
          onChanged: (d) => emitted = d,
        ),
      );

      await choose(tester, 'Nadar');
      expect(emitted?.community, 'Nadar');
      // A community belonging to another religion is not on offer.
      expect(ProfileOptions.communitiesFor('Hindu'), contains('Nadar'));
      expect(ProfileOptions.communitiesFor('Jain'), isNot(contains('Nadar')));
    });

    testWidgets('changing religion clears a community it does not offer', (
      tester,
    ) async {
      ReligionDetails? emitted;
      await pump(
        tester,
        StepReligion(
          details: const ReligionDetails(
            religion: 'Hindu',
            community: 'Nadar',
            subCaste: 'Vadama',
          ),
          onChanged: (d) => emitted = d,
        ),
      );

      await choose(tester, 'Jain');

      // 'Nadar' is not a Jain community, so it goes — along with the
      // sub-community that only made sense underneath it.
      expect(emitted?.religion, 'Jain');
      expect(emitted?.community, isEmpty);
      expect(emitted?.subCaste, isEmpty);
    });

    testWidgets('keeps a community the new religion still offers', (
      tester,
    ) async {
      ReligionDetails? emitted;
      await pump(
        tester,
        StepReligion(
          details: const ReligionDetails(
            religion: 'Hindu',
            community: 'Tamil',
          ),
          onChanged: (d) => emitted = d,
        ),
      );

      await choose(tester, 'Christian');

      // 'Tamil' is offered under both, so re-picking a religion must not cost
      // an answer that is still true.
      expect(ProfileOptions.communitiesFor('Christian'), contains('Tamil'));
      expect(emitted?.community, 'Tamil');
    });
  });

  // ─── Country → state → city ─────────────────────────────────────────

  group('country drives state drives city', () {
    testWidgets('changing country clears a state it does not offer', (
      tester,
    ) async {
      LocationDetails? emitted;
      await pump(
        tester,
        StepLocation(
          details: const LocationDetails(
            country: 'India',
            state: 'Tamil Nadu',
            city: 'Chennai',
          ),
          onChanged: (d) => emitted = d,
        ),
      );

      await choose(tester, 'Canada');

      expect(emitted?.country, 'Canada');
      expect(emitted?.state, isEmpty);
      expect(emitted?.city, isEmpty);
    });

    testWidgets('changing state clears a city it does not offer', (
      tester,
    ) async {
      LocationDetails? emitted;
      await pump(
        tester,
        StepLocation(
          details: const LocationDetails(
            country: 'India',
            state: 'Tamil Nadu',
            city: 'Chennai',
          ),
          onChanged: (d) => emitted = d,
        ),
      );

      await choose(tester, 'Karnataka');

      expect(emitted?.state, 'Karnataka');
      expect(emitted?.city, isEmpty);
      expect(ProfileOptions.citiesFor('Karnataka'), isNot(contains('Chennai')));
    });

    test('states are scoped to their country', () {
      expect(ProfileOptions.statesFor('India'), contains('Tamil Nadu'));
      expect(ProfileOptions.statesFor('Canada'), contains('Ontario'));
      expect(
        ProfileOptions.statesFor('Canada'),
        isNot(contains('Tamil Nadu')),
      );
      // An unknown country falls back rather than showing an empty dropdown.
      expect(ProfileOptions.statesFor('Atlantis'), ProfileOptions.states);
    });
  });

  // ─── Not losing what is already stored ──────────────────────────────

  group('an unavailable stored value survives', () {
    testWidgets('a state the curated list does not carry stays selected', (
      tester,
    ) async {
      LocationDetails? emitted;
      await pump(
        tester,
        StepLocation(
          // 'Goa' is a real answer the wizard's list has never offered.
          details: const LocationDetails(
            country: 'India',
            state: 'Goa',
            city: 'Panaji',
          ),
          onChanged: (d) => emitted = d,
        ),
      );

      expect(find.text('Goa'), findsOneWidget);
      expect(find.text('Panaji'), findsOneWidget);

      // Touching an unrelated field must not quietly rewrite them.
      await tester.enterText(find.byType(TextFormField).last, 'Madgaon');
      await tester.pumpAndSettle();
      expect(emitted?.state, 'Goa');
      expect(emitted?.city, 'Panaji');
    });

    testWidgets('an old employmentType value stays selected', (tester) async {
      EducationDetails? emitted;
      await pump(
        tester,
        StepEducation(
          details: const EducationDetails(
            employmentType: 'Self-Employed',
            company: 'Own firm',
          ),
          onChanged: (d) => emitted = d,
        ),
      );

      // Every value stored before the dropdown existed is still offered.
      expect(find.text('Self-Employed'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'B.Com');
      await tester.pumpAndSettle();
      expect(emitted?.employmentType, 'Self-Employed');
    });
  });

  // ─── The work section ───────────────────────────────────────────────

  group('the work section', () {
    test('offers every previously stored employment type', () {
      for (final stored in const [
        'Private',
        'Government',
        'Business',
        'Self-Employed',
        'Not Working',
        'Student',
      ]) {
        expect(ProfileOptions.employmentTypes, contains(stored));
      }
      // Retired was genuinely missing and is the only addition.
      expect(ProfileOptions.employmentTypes, contains('Retired'));
    });

    test('industry comes from the shared list, not a screen-local copy', () {
      expect(ProfileOptions.industries, contains('IT / Software'));
      expect(ProfileOptions.industries, contains('Healthcare'));
    });

    testWidgets('emits industry as its own field', (tester) async {
      EducationDetails? emitted;
      await pump(
        tester,
        StepEducation(
          details: const EducationDetails(),
          onChanged: (d) => emitted = d,
        ),
      );

      await choose(tester, 'Healthcare');
      expect(emitted?.workIndustry, 'Healthcare');
      // And it travels as its own key, not folded into another field.
      expect(emitted?.toJson()['workIndustry'], 'Healthcare');
    });
  });

  // ─── Optional sub-community ─────────────────────────────────────────

  test('an empty sub-community is omitted from the payload entirely', () {
    const answered = ReligionDetails(religion: 'Hindu', community: 'Nadar');
    expect(answered.toJson().containsKey('subCaste'), isFalse);
    expect(answered.toJson()['religion'], 'Hindu');

    const withSub = ReligionDetails(
      religion: 'Hindu',
      community: 'Nadar',
      subCaste: 'Vadama',
    );
    expect(withSub.toJson()['subCaste'], 'Vadama');
  });

  // ─── The serializer the whole flow shares ───────────────────────────

  test('every work answer round-trips through the one serializer', () {
    const details = EducationDetails(
      qualification: 'B.E / B.Tech',
      college: 'Anna University',
      annualIncome: 'Rs. 10 - 15 Lakhs',
      employmentType: 'Private',
      workIndustry: 'IT / Software',
      occupation: 'Software Engineer',
      company: 'Acme',
      workLocation: 'Chennai',
    );
    final json = details.toJson();
    expect(json['employmentType'], 'Private');
    expect(json['workIndustry'], 'IT / Software');
    expect(json['occupation'], 'Software Engineer');
    expect(json['company'], 'Acme');
    expect(json['college'], 'Anna University');

    final restored = EducationDetails.fromJson(json);
    expect(restored.workIndustry, 'IT / Software');
    expect(restored.employmentType, 'Private');
    expect(restored.college, 'Anna University');
  });
}
