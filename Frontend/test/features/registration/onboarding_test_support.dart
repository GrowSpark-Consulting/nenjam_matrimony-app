import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nenjam_matrimony/core/widgets/inputs/birth_date_field.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';
import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:nenjam_matrimony/features/location/data/location_repository.dart';
import 'package:nenjam_matrimony/features/location/domain/models/location_models.dart';
import 'package:nenjam_matrimony/features/location/presentation/providers/location_providers.dart';
import 'package:nenjam_matrimony/features/religion/data/religion_repository.dart';
import 'package:nenjam_matrimony/features/religion/presentation/providers/religion_providers.dart';
import 'package:nenjam_matrimony/features/location/presentation/widgets/location_picker_field.dart';
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/create_profile_for_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Shared harness for the onboarding step tests. Each step screen persists
/// through [RegistrationRepository], navigates with `context.go`, and lays
/// out a headline plus fields plus a pinned CTA — so all of them need the
/// same three things, and none of them should carry a private copy.

/// Records what a step sent to the backend, and can be told to fail, so a
/// test can assert both that the answers persist and that a failure keeps
/// the member on the screen.
///
/// `implements` rather than `extends`: only the calls onboarding makes are
/// stubbed, and [noSuchMethod] deliberately throws for anything else so a
/// step that starts calling a new endpoint fails loudly here instead of
/// silently doing nothing.
class RecordingRegistrationRepository implements RegistrationRepository {
  RecordingRegistrationRepository({
    this.failLocation = false,
    this.failReligion = false,
  });

  final bool failLocation;
  final bool failReligion;

  LocationDetails? savedLocation;
  ReligionDetails? savedReligion;
  LanguageDetails? savedLanguage;
  BasicDetails? savedBasic;
  PartnerPreference? savedPartnerPreference;
  PhysicalDetails? savedPhysical;
  EducationDetails? savedEducation;
  LifestyleDetails? savedLifestyle;
  FamilyDetails? savedFamily;
  HoroscopeDetails? savedHoroscope;

  /// How many times `POST /profiles/finalize` was asked for. Editing must
  /// not need it — see edit_profile_save_test.dart.
  int finalizeCalls = 0;

  /// The `skipMaterialize` flag of each section save, in call order. A save
  /// that skips materialization does not rewrite `user_profiles`, so which
  /// call materializes (and that exactly one does) is part of the contract.
  final List<bool> skipMaterializeFlags = <bool>[];

  /// Every section name this recorder was asked to save, in call order.
  /// The individual `saved*` fields answer "what was sent"; this answers
  /// "was it sent at all", which is what
  /// [RegistrationNotifier.flushOnboardingToBackend] regressed on.
  final List<String> savedSections = <String>[];

  /// The sections onboarding writes: `gender` and `profileCreatedFor` from
  /// Profile For, the name and date of birth from Your Name, religion and
  /// country from Your Religion, and location from "Let's build your
  /// Profile". `caste` and `motherTongue` are NOT among them — onboarding no
  /// longer collects either, which is why no step here sends them.
  @override
  Future<void> updateBasicDetails(
    BasicDetails details, {
    bool skipMaterialize = false,
  }) async {
    skipMaterializeFlags.add(skipMaterialize);
    savedSections.add('basicDetails');
    savedBasic = details;
  }

  @override
  Future<void> updateLanguageDetails(
    LanguageDetails details, {
    bool skipMaterialize = false,
  }) async {
    skipMaterializeFlags.add(skipMaterialize);
    savedSections.add('languageDetails');
    savedLanguage = details;
  }

  @override
  Future<void> updateLocationDetails(
    LocationDetails details, {
    bool skipMaterialize = false,
  }) async {
    if (failLocation) throw Exception('location save failed');
    skipMaterializeFlags.add(skipMaterialize);
    savedSections.add('locationDetails');
    savedLocation = details;
  }

  @override
  Future<void> updateReligionDetails(
    ReligionDetails details, {
    bool skipMaterialize = false,
  }) async {
    if (failReligion) throw Exception('religion save failed');
    skipMaterializeFlags.add(skipMaterialize);
    savedSections.add('religionDetails');
    savedReligion = details;
  }

  @override
  Future<void> updatePartnerPreference(
    PartnerPreference details, {
    bool skipMaterialize = false,
  }) async {
    skipMaterializeFlags.add(skipMaterialize);
    savedSections.add('partnerPreference');
    savedPartnerPreference = details;
  }

  // The remaining three sections the end-of-onboarding flush sends. Stubbed
  // so that flush can be exercised end to end: it stops at its first failure
  // and throws it, so an unstubbed call would abort the run through
  // `noSuchMethod` and hide whichever sections came after it.
  @override
  Future<void> updatePhysicalDetails(
    PhysicalDetails details, {
    bool skipMaterialize = false,
  }) async {
    skipMaterializeFlags.add(skipMaterialize);
    savedSections.add('physicalDetails');
    savedPhysical = details;
  }

  @override
  Future<void> updateEducationDetails(
    EducationDetails details, {
    bool skipMaterialize = false,
  }) async {
    skipMaterializeFlags.add(skipMaterialize);
    savedSections.add('educationDetails');
    savedEducation = details;
  }

  @override
  Future<void> updateLifestyleDetails(
    LifestyleDetails details, {
    bool skipMaterialize = false,
  }) async {
    skipMaterializeFlags.add(skipMaterialize);
    savedSections.add('lifestyleDetails');
    savedLifestyle = details;
  }

  @override
  Future<void> updateFamilyDetails(
    FamilyDetails details, {
    bool skipMaterialize = false,
  }) async {
    skipMaterializeFlags.add(skipMaterialize);
    savedSections.add('familyDetails');
    savedFamily = details;
  }

  @override
  Future<void> updateHoroscopeDetails(
    HoroscopeDetails details, {
    bool skipMaterialize = false,
  }) async {
    skipMaterializeFlags.add(skipMaterialize);
    savedSections.add('horoscopeDetails');
    savedHoroscope = details;
  }

  @override
  Future<Map<String, dynamic>> finalizeProfile() async {
    finalizeCalls++;
    return <String, dynamic>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A signed-in account. Onboarding only sends a step to the backend when a
/// session exists — signed out it persists locally instead — so a test that
/// asserts on what the repository received has to supply one.
class SignedInAuthService implements FirebaseAuthService {
  @override
  User? get currentUser => _StubUser();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubUser implements User {
  @override
  String get uid => 'test-uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Tall enough that every field and the CTA are laid out at once; the
/// default 800x600 surface scrolls the last of them off.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget harness(ProviderContainer container, GoRouter router) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

/// Opens the dropdown at [index] (in top-to-bottom screen order) and picks
/// [option]. `.last` because the chosen value also renders in the closed
/// button, so the menu entry is the second match.
Future<void> pickDropdown(
  WidgetTester tester,
  int index,
  String option,
) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// Answers the gender pills on the Profile For step, which is where gender is
/// asked now. `user_profiles.gender` is NOT NULL, so no screen after this one
/// can make up for skipping it.
Future<void> pickGender(WidgetTester tester, {String gender = 'Male'}) async {
  await tester.tap(find.widgetWithText(ProfileForChoicePill, gender));
  await tester.pumpAndSettle();
}

/// Answers the "Let's build your Profile" step: its two required fields, and
/// the optional sub-community alongside them.
Future<void> fillBasics(
  WidgetTester tester, {
  String state = 'Gujarat',
  String city = 'Bhavnagar',
  String subCommunity = 'Iyer',
}) async {
  // State and city come from the backend's master data now, so they open the
  // searchable sheet rather than a dropdown.
  await pickLocation(tester, 'State *', state);
  await pickLocation(tester, 'City *', city);
  // Sub-community is the only text field on the step.
  if (subCommunity.isNotEmpty) {
    await tester.enterText(find.byType(TextFormField).first, subCommunity);
    await tester.pumpAndSettle();
  }
}

/// A date of birth comfortably past the age floor, used wherever a step test
/// just needs the date answered rather than a particular one.
DateTime defaultDob() => DateTime(1998, 8, 15);

/// Types [date] into the Your Name step's three Day / Month / Year boxes.
///
/// The boxes are the last three text fields on the step, after first and last
/// name — the field is [NmBirthDateField], not a calendar, so a test answers
/// it the way a member does.
Future<DateTime> enterDob(WidgetTester tester, [DateTime? date]) async {
  final dob = date ?? defaultDob();
  final boxes = find.descendant(
    of: find.byType(NmBirthDateField),
    matching: find.byType(TextFormField),
  );
  await tester.enterText(boxes.at(0), dob.day.toString().padLeft(2, '0'));
  await tester.enterText(boxes.at(1), dob.month.toString().padLeft(2, '0'));
  await tester.enterText(boxes.at(2), dob.year.toString());
  await tester.pumpAndSettle();
  return dob;
}

/// Fills the Your Name step end to end: both names and a typed date.
Future<DateTime> fillNameStep(
  WidgetTester tester, {
  String firstName = 'Arjun',
  String lastName = 'Krishnan',
  DateTime? dob,
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), firstName);
  await tester.enterText(find.byType(TextFormField).at(1), lastName);
  await tester.pumpAndSettle();
  return enterDob(tester, dob);
}

// ─── Location master data ────────────────────────────────────────────────

/// A stand-in for the backend's location master data.
///
/// Deliberately small but *shaped* like the real thing — ISO codes, a state
/// scoped to its country, a city scoped to its state — because the codes are
/// what the cascade and the server both key on. Onboarding must never reach
/// the network in a test, and it must never fall back to a hardcoded list
/// either, so every location test supplies this.
class FakeLocationRepository implements LocationRepository {
  FakeLocationRepository({
    this.failCountries = false,
    this.failStates = false,
    this.failCities = false,
    bool holdCountries = false,
    bool holdStates = false,
    bool holdCities = false,
    this.cityDelay = const {},
  })  : _countriesGate = holdCountries ? Completer<void>() : null,
        _statesGate = holdStates ? Completer<void>() : null,
        _citiesGate = holdCities ? Completer<void>() : null;

  final bool failCountries;

  /// Mutable, unlike [failCountries]: a retry test flips this off between the
  /// failed load and the "Try again" tap, so the same fake can serve both a
  /// failure and the successful retry that follows it.
  bool failStates;
  bool failCities;

  /// Per-state-code delay, for a city-cascade stale-response test — the
  /// location equivalent of `_StubReligionRepository.communityDelay`.
  final Map<String, Duration> cityDelay;

  /// When set, `countries()` waits here until [releaseCountries] is called.
  ///
  /// Lets a test hold the first request in flight and then trigger a second
  /// caller, which is the only way to prove the two are actually deduplicated
  /// rather than merely fast enough that the first finished in between.
  final Completer<void>? _countriesGate;

  /// Same idea as [_countriesGate], for `states()` — lets a test observe the
  /// State field's loading skeleton before the list resolves.
  final Completer<void>? _statesGate;

  /// Same idea as [_countriesGate], for `cities()` — lets a test observe the
  /// City field's loading skeleton before the list resolves.
  final Completer<void>? _citiesGate;

  /// Lets a held `countries()` call complete.
  void releaseCountries() {
    if (_countriesGate != null && !_countriesGate.isCompleted) {
      _countriesGate.complete();
    }
  }

  /// Lets a held `states()` call complete.
  void releaseStates() {
    if (_statesGate != null && !_statesGate.isCompleted) {
      _statesGate.complete();
    }
  }

  /// Lets a held `cities()` call complete.
  void releaseCities() {
    if (_citiesGate != null && !_citiesGate.isCompleted) {
      _citiesGate.complete();
    }
  }

  /// Every request made, so a test can assert the cascade only fetches what
  /// the member's selection actually calls for.
  final List<String> calls = <String>[];

  static const country = LocationOption(code: 'IN', label: 'India');
  static const otherCountry = LocationOption(code: 'CA', label: 'Canada');
  static const state = LocationOption(
    code: 'IN-GJ',
    label: 'Gujarat',
    parentCode: 'IN',
    type: 'State',
  );
  static const otherState = LocationOption(
    code: 'IN-TN',
    label: 'Tamil Nadu',
    parentCode: 'IN',
    type: 'State',
  );
  static const city = LocationOption(
    code: 'IN-GJ-BHAVNAGAR',
    label: 'Bhavnagar',
    parentCode: 'IN-GJ',
  );
  static const otherCity = LocationOption(
    code: 'IN-GJ-AHMEDABAD',
    label: 'Ahmedabad',
    parentCode: 'IN-GJ',
  );
  static const tnCity = LocationOption(
    code: 'IN-TN-CHENNAI',
    label: 'Chennai',
    parentCode: 'IN-TN',
  );

  @override
  Future<List<LocationOption>> countries({CancelToken? cancelToken}) async {
    calls.add('countries');
    if (_countriesGate != null) await _countriesGate.future;
    if (failCountries) throw Exception('offline');
    return const [country, otherCountry];
  }

  @override
  Future<List<LocationOption>> states(
    String countryCode, {
    CancelToken? cancelToken,
  }) async {
    calls.add('states:$countryCode');
    if (_statesGate != null) await _statesGate.future;
    if (failStates) throw Exception('offline');
    if (countryCode == 'IN') return const [state, otherState];
    return const [];
  }

  @override
  Future<List<LocationOption>> cities(
    String stateCode, {
    CancelToken? cancelToken,
  }) async {
    calls.add('cities:$stateCode');
    if (_citiesGate != null) await _citiesGate.future;
    final delay = cityDelay[stateCode];
    if (delay != null) await Future<void>.delayed(delay);
    if (failCities) throw Exception('offline');
    return switch (stateCode) {
      'IN-GJ' => const [city, otherCity],
      'IN-TN' => const [tnCity],
      _ => const [],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// How many times the country list was requested. The number that matters
/// for the prefetch: it must stay at one however many screens ask.
extension FakeLocationCallCounts on FakeLocationRepository {
  int get countryRequests => calls.where((c) => c == 'countries').length;
}

/// Serves the Religion step's two reference-data levels.
///
/// The onboarding Religion screen reads religion and community from the
/// backend now, exactly as it reads the country, so any test that renders
/// that screen needs this or the step can never be completed.
class FakeReligionRepository implements ReligionRepository {
  FakeReligionRepository({
    this.failReligions = false,
    this.failCommunities = false,
    bool holdReligions = false,
    bool holdCommunities = false,
    this.communityDelay = const {},
  })  : _religionsGate = holdReligions ? Completer<void>() : null,
        _communitiesGate = holdCommunities ? Completer<void>() : null;

  /// Mutable, so a retry test can flip either of these off between the
  /// failed load and the "Try again" tap.
  bool failReligions;
  bool failCommunities;

  /// Per-religion-code delay, for a community-cascade stale-response test.
  final Map<String, Duration> communityDelay;

  /// Lets a test observe the Religion field's loading skeleton before the
  /// list resolves — the same idea as [FakeLocationRepository]'s gates.
  final Completer<void>? _religionsGate;
  final Completer<void>? _communitiesGate;

  /// Lets a held `religions()` call complete.
  void releaseReligions() {
    if (_religionsGate != null && !_religionsGate.isCompleted) {
      _religionsGate.complete();
    }
  }

  /// Lets a held `communities()` call complete.
  void releaseCommunities() {
    if (_communitiesGate != null && !_communitiesGate.isCompleted) {
      _communitiesGate.complete();
    }
  }

  static const _religions = [
    LocationOption(code: 'HINDU', label: 'Hindu'),
    LocationOption(code: 'JAIN', label: 'Jain'),
  ];

  static const _byReligion = {
    'HINDU': [
      LocationOption(code: 'HINDU-IYER', label: 'Iyer', parentCode: 'HINDU'),
      LocationOption(code: 'HINDU-NADAR', label: 'Nadar', parentCode: 'HINDU'),
    ],
    'JAIN': [
      LocationOption(code: 'JAIN-DIGAMBAR', label: 'Digambar', parentCode: 'JAIN'),
    ],
  };

  @override
  Future<List<LocationOption>> religions({dynamic cancelToken}) async {
    if (_religionsGate != null) await _religionsGate.future;
    if (failReligions) throw Exception('religions unavailable');
    return _religions;
  }

  @override
  Future<List<LocationOption>> communities(
    String religionCode, {
    dynamic cancelToken,
  }) async {
    if (_communitiesGate != null) await _communitiesGate.future;
    final delay = communityDelay[religionCode];
    if (delay != null) await Future<void>.delayed(delay);
    if (failCommunities) throw Exception('communities unavailable');
    return _byReligion[religionCode] ?? const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The overrides every onboarding reference-data test needs. Kept as one call
/// so a test cannot accidentally leave a real repository in place and start
/// making requests.
///
/// Covers BOTH cascades on the onboarding path — country → state → city and
/// religion → community — because the Religion screen renders fields from
/// each, and a missing religion stub shows up as an unrelated "Could not
/// load" in a location assertion.
List<Override> locationOverrides(
  FakeLocationRepository repository, {
  FakeReligionRepository? religions,
}) =>
    [
      locationRepositoryProvider.overrideWithValue(repository),
      religionRepositoryProvider
          .overrideWithValue(religions ?? FakeReligionRepository()),
    ];

/// Fills the Religion step's religion and community fields.
///
/// They are no longer `DropdownButtonFormField`s — both open the app's
/// searchable sheet, like the location levels — so [pickDropdown] cannot
/// drive them and index-based selection no longer applies.
Future<void> fillReligionStep(
  WidgetTester tester, {
  String religion = 'Hindu',
  String community = 'Iyer',
}) async {
  await pickLocation(tester, 'Religion *', religion);
  await pickLocation(tester, 'Community *', community);
}

/// Picks [option] from the location field headed [label].
///
/// Location levels are not `DropdownButtonFormField`s — they open the app's
/// searchable sheet — so [pickDropdown] cannot drive them. Finding by the
/// field's own heading rather than by index keeps a test readable and stops
/// it breaking when a field moves.
Future<void> pickLocation(
  WidgetTester tester,
  String label,
  String option,
) async {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byType(LocationPickerField),
  );
  expect(field, findsOneWidget, reason: 'no location field headed "$label"');
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}
