import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/constants/profile_options.dart';
import 'package:nenjam_matrimony/features/location/data/location_repository.dart';
import 'package:nenjam_matrimony/features/location/domain/models/location_models.dart';
import 'package:nenjam_matrimony/features/location/presentation/providers/location_providers.dart';
import 'package:nenjam_matrimony/features/location/presentation/widgets/location_picker_field.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/step_basic_info.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/step_education.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/step_location.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/step_religion.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'onboarding_test_support.dart';

/// Stands in for the network in the location cascade tests.
///
/// Small on purpose: enough countries, states and cities to prove the cascade
/// clears what it should, and no more. Real codes throughout, so a test
/// asserting `IN-TN-CHENNAI` is asserting the shape the backend actually
/// returns.
class _StubLocationRepository implements LocationRepository {
  static const _countries = [
    LocationOption(code: 'IN', label: 'India'),
    LocationOption(code: 'CA', label: 'Canada'),
  ];

  static const _states = {
    'IN': [
      LocationOption(code: 'IN-TN', label: 'Tamil Nadu', parentCode: 'IN', type: 'State'),
      LocationOption(code: 'IN-KA', label: 'Karnataka', parentCode: 'IN', type: 'State'),
    ],
    'CA': [
      LocationOption(code: 'CA-ON', label: 'Ontario', parentCode: 'CA', type: 'Province'),
    ],
  };

  static const _cities = {
    'IN-TN': [
      LocationOption(code: 'IN-TN-CHENNAI', label: 'Chennai', parentCode: 'IN-TN'),
      LocationOption(code: 'IN-TN-MADURAI', label: 'Madurai', parentCode: 'IN-TN'),
    ],
    'IN-KA': [
      LocationOption(code: 'IN-KA-BENGALURU', label: 'Bengaluru', parentCode: 'IN-KA'),
    ],
    'CA-ON': [
      LocationOption(code: 'CA-ON-TORONTO', label: 'Toronto', parentCode: 'CA-ON'),
    ],
  };

  @override
  Future<List<LocationOption>> countries({dynamic cancelToken}) async => _countries;

  @override
  Future<List<LocationOption>> states(String countryCode, {dynamic cancelToken}) async =>
      _states[countryCode] ?? const [];

  @override
  Future<List<LocationOption>> cities(String stateCode, {dynamic cancelToken}) async =>
      _cities[stateCode] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  // ─── Location harness ───────────────────────────────────────────────
  //
  // StepLocation reads country/state/city from the backend's master data now,
  // so it needs a ProviderScope and a repository. This stub stands in for the
  // network: the step's own logic is what these tests are about.

  /// Pumps [StepLocation] with a stubbed location repository.
  Future<void> pumpLocation(WidgetTester tester, StepLocation step) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationRepositoryProvider.overrideWithValue(_StubLocationRepository()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: step),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Opens the picker labelled [field]'s selection sheet.
  ///
  /// The label is a sibling of the tappable region, not its parent, so this
  /// walks up to the [LocationPickerField] and taps its InkWell.
  Future<void> openPicker(WidgetTester tester, String field) async {
    final picker = find.ancestor(
      of: find.text(field),
      matching: find.byType(LocationPickerField),
    );
    final target = find.descendant(of: picker, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Opens the picker labelled [field] and taps [option] in the sheet.
  Future<void> pick(WidgetTester tester, String field, String option) async {
    await openPicker(tester, field);
    // The sheet lists options as ListTiles.
    await tester.tap(find.widgetWithText(ListTile, option).last);
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
    /// A profile already saved against the master data — codes and all.
    const saved = LocationDetails(
      country: 'India',
      state: 'Tamil Nadu',
      city: 'Chennai',
      countryCode: 'IN',
      stateCode: 'IN-TN',
      cityCode: 'IN-TN-CHENNAI',
    );

    testWidgets('changing country clears the state and city beneath it', (
      tester,
    ) async {
      LocationDetails? emitted;
      await pumpLocation(
        tester,
        StepLocation(details: saved, onChanged: (d) => emitted = d),
      );

      await pick(tester, 'Country', 'Canada');

      expect(emitted?.country, 'Canada');
      expect(emitted?.countryCode, 'CA');
      // Tamil Nadu under Canada is a combination the server rejects, so the
      // step must not be able to emit it.
      expect(emitted?.state, isEmpty);
      expect(emitted?.stateCode, isEmpty);
      expect(emitted?.city, isEmpty);
      expect(emitted?.cityCode, isEmpty);
    });

    testWidgets('changing state clears the city but keeps the country', (
      tester,
    ) async {
      LocationDetails? emitted;
      await pumpLocation(
        tester,
        StepLocation(details: saved, onChanged: (d) => emitted = d),
      );

      await pick(tester, 'State', 'Karnataka');

      expect(emitted?.countryCode, 'IN');
      expect(emitted?.state, 'Karnataka');
      expect(emitted?.stateCode, 'IN-KA');
      expect(emitted?.city, isEmpty);
      expect(emitted?.cityCode, isEmpty);
    });

    testWidgets('emits the code alongside the label when a city is picked', (
      tester,
    ) async {
      LocationDetails? emitted;
      await pumpLocation(
        tester,
        StepLocation(details: saved, onChanged: (d) => emitted = d),
      );

      await pick(tester, 'City', 'Madurai');

      // Both halves travel together: the label is what the member reads back,
      // the code is what the server validates and stores.
      expect(emitted?.city, 'Madurai');
      expect(emitted?.cityCode, 'IN-TN-MADURAI');
    });

    testWidgets('a state list is scoped to its country', (tester) async {
      await pumpLocation(
        tester,
        StepLocation(
          details: const LocationDetails(
            country: 'Canada',
            countryCode: 'CA',
          ),
          onChanged: (_) {},
        ),
      );

      await openPicker(tester, 'State');

      expect(find.widgetWithText(ListTile, 'Ontario'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Tamil Nadu'), findsNothing);
    });
  });

  // ─── Not losing what is already stored ──────────────────────────────

  group('an unavailable stored value survives', () {
    testWidgets('a location saved before the master data existed is not lost', (
      tester,
    ) async {
      LocationDetails? emitted;
      await pumpLocation(
        tester,
        StepLocation(
          // Text with no codes — every profile written before the location
          // master data shipped looks exactly like this.
          details: const LocationDetails(
            country: 'India',
            state: 'Goa',
            city: 'Panaji',
          ),
          onChanged: (d) => emitted = d,
        ),
      );

      // The member sees the answer they gave, not an empty field that looks
      // like the app lost it.
      expect(find.text('Goa'), findsOneWidget);
      expect(find.text('Panaji'), findsOneWidget);

      // Touching an unrelated field must not quietly rewrite them. This is
      // the regression that matters: emitting empty strings here would wipe
      // the stored location of every member who edits their profile.
      await tester.enterText(find.byType(TextFormField).last, 'Madgaon');
      await tester.pumpAndSettle();
      expect(emitted?.country, 'India');
      expect(emitted?.state, 'Goa');
      expect(emitted?.city, 'Panaji');
      // No codes are invented for them — the backend reads that as "no
      // structured location" and keeps using the text.
      expect(emitted?.countryCode, isEmpty);
      expect(emitted?.stateCode, isEmpty);
      expect(emitted?.cityCode, isEmpty);
    });

    testWidgets('replacing a legacy country clears its legacy children', (
      tester,
    ) async {
      LocationDetails? emitted;
      await pumpLocation(
        tester,
        StepLocation(
          details: const LocationDetails(
            country: 'India',
            state: 'Goa',
            city: 'Panaji',
          ),
          onChanged: (d) => emitted = d,
        ),
      );

      await pick(tester, 'Country', 'Canada');

      // A leftover "Panaji" must not survive the member choosing Canada.
      expect(emitted?.countryCode, 'CA');
      expect(emitted?.state, isEmpty);
      expect(emitted?.city, isEmpty);
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
