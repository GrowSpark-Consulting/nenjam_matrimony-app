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
  PartnerPreference? savedPartnerPreference;

  @override
  Future<void> updateLocationDetails(
    LocationDetails details, {
    bool skipMaterialize = false,
  }) async {
    if (failLocation) throw Exception('location save failed');
    savedLocation = details;
  }

  @override
  Future<void> updateReligionDetails(
    ReligionDetails details, {
    bool skipMaterialize = false,
  }) async {
    if (failReligion) throw Exception('religion save failed');
    savedReligion = details;
  }

  @override
  Future<void> updatePartnerPreference(
    PartnerPreference details, {
    bool skipMaterialize = false,
  }) async {
    savedPartnerPreference = details;
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
