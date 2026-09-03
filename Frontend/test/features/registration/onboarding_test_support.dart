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

  /// Onboarding writes these two now: `caste`/`motherTongue` from the
  /// Religion step and `firstName`/`lastName`/`gender`/`dob` from Profile
  /// Basics. Every one of them is a NOT NULL column on `user_profiles`, so
  /// without these calls the backend never materializes a profile row at all.
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

/// Opens the date-of-birth calendar and accepts the date it opens on.
///
/// The field is a read-only [TextFormField] behind an [AbsorbPointer], so the
/// tap is aimed at the enclosing [GestureDetector] rather than the icon —
/// tapping the icon lands, but only by falling through the absorber, which
/// makes the test framework warn about a missed hit test. The picker's
/// `initialDate` is already a valid answer (25 years ago), so confirming is
/// all a test needs.
Future<void> pickDob(WidgetTester tester) async {
  await tester.tap(
    find
        .ancestor(
          of: find.byIcon(Icons.calendar_today_rounded),
          matching: find.byType(GestureDetector),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Answers the identity half of the Profile Basics step: the name, gender and
/// date of birth backing `user_profiles`' NOT NULL `first_name`, `last_name`,
/// `gender` and `dob` columns. State and city are left to the caller, since
/// several tests vary them.
Future<void> fillIdentity(
  WidgetTester tester, {
  String firstName = 'Arjun',
  String lastName = 'Krishnan',
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), firstName);
  await tester.enterText(find.byType(TextFormField).at(1), lastName);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ChoiceChip, 'Male'));
  await tester.pumpAndSettle();
  await pickDob(tester);
}
