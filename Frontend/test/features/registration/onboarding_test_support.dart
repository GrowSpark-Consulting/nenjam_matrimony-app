import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
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
    savedSections.add('basicDetails');
    savedBasic = details;
  }

  @override
  Future<void> updateLanguageDetails(
    LanguageDetails details, {
    bool skipMaterialize = false,
  }) async {
    savedSections.add('languageDetails');
    savedLanguage = details;
  }

  @override
  Future<void> updateLocationDetails(
    LocationDetails details, {
    bool skipMaterialize = false,
  }) async {
    if (failLocation) throw Exception('location save failed');
    savedSections.add('locationDetails');
    savedLocation = details;
  }

  @override
  Future<void> updateReligionDetails(
    ReligionDetails details, {
    bool skipMaterialize = false,
  }) async {
    if (failReligion) throw Exception('religion save failed');
    savedSections.add('religionDetails');
    savedReligion = details;
  }

  @override
  Future<void> updatePartnerPreference(
    PartnerPreference details, {
    bool skipMaterialize = false,
  }) async {
    savedSections.add('partnerPreference');
    savedPartnerPreference = details;
  }

  // The remaining three sections the end-of-onboarding flush sends. Stubbed
  // so that flush can be exercised end to end: it swallows its own errors, so
  // an unstubbed call would abort the run through `noSuchMethod` and be
  // silently discarded, hiding whichever sections came after it.
  @override
  Future<void> updatePhysicalDetails(
    PhysicalDetails details, {
    bool skipMaterialize = false,
  }) async {
    savedSections.add('physicalDetails');
    savedPhysical = details;
  }

  @override
  Future<void> updateEducationDetails(
    EducationDetails details, {
    bool skipMaterialize = false,
  }) async {
    savedSections.add('educationDetails');
    savedEducation = details;
  }

  @override
  Future<void> updateLifestyleDetails(
    LifestyleDetails details, {
    bool skipMaterialize = false,
  }) async {
    savedSections.add('lifestyleDetails');
    savedLifestyle = details;
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

/// Answers the gender chips on the Profile For step, which is where gender is
/// asked now. `user_profiles.gender` is NOT NULL, so no screen after this one
/// can make up for skipping it.
Future<void> pickGender(WidgetTester tester, {String gender = 'Male'}) async {
  await tester.tap(find.widgetWithText(ChoiceChip, gender));
  await tester.pumpAndSettle();
}

/// Answers the "Let's build your Profile" step: its two required fields, and
/// the optional sub-community alongside them.
Future<void> fillBasics(
  WidgetTester tester, {
  String state = 'Tamil Nadu',
  String city = 'Chennai',
  String subCommunity = 'Iyer',
}) async {
  await pickDropdown(tester, 0, state);
  await pickDropdown(tester, 1, city);
  // Sub-community is the only text field on the step.
  if (subCommunity.isNotEmpty) {
    await tester.enterText(find.byType(TextFormField).first, subCommunity);
    await tester.pumpAndSettle();
  }
}

/// Types a whole date of birth into the Your Name step's three boxes. The
/// default is comfortably over 18 and comfortably after 1950, so a test that
/// is not about date validation never trips either bound.
Future<void> enterDob(
  WidgetTester tester, {
  String day = '05',
  String month = '02',
  String year = '1998',
  int firstFieldIndex = 2,
}) async {
  await tester.enterText(find.byType(TextFormField).at(firstFieldIndex), day);
  await tester.enterText(
    find.byType(TextFormField).at(firstFieldIndex + 1),
    month,
  );
  await tester.enterText(
    find.byType(TextFormField).at(firstFieldIndex + 2),
    year,
  );
  await tester.pumpAndSettle();
}

/// Fills the Your Name step end to end: both names and a valid date.
Future<void> fillNameStep(
  WidgetTester tester, {
  String firstName = 'Arjun',
  String lastName = 'Krishnan',
  String day = '05',
  String month = '02',
  String year = '1998',
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), firstName);
  await tester.enterText(find.byType(TextFormField).at(1), lastName);
  await tester.pumpAndSettle();
  await enterDob(tester, day: day, month: month, year: year);
}
