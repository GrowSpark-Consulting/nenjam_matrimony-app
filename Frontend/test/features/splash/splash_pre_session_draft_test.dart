import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/features/splash/presentation/providers/splash_provider.dart';

/// Stands in for `FirebaseAuth.instance` itself so nothing on the provider
/// graph reaches the real SDK. `authRepositoryProvider` watches
/// `firebaseAuthServiceProvider` (via [_FakeAuthService] below) AND
/// `googleAuthServiceProvider`, and the latter constructs a real
/// `GoogleAuthService` from `ref.watch(firebaseAuthProvider)` directly — so
/// faking the service alone still leaves that second path hitting
/// `FirebaseAuth.instance`. Overriding the SDK provider covers both.
class _FakeFirebaseAuth implements FirebaseAuth {
  const _FakeFirebaseAuth();

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Same pattern as `post_auth_destination_test.dart`'s `_FakeAuthService`.
/// [SplashController.resolveInitialRoute] reads `authRepositoryProvider`
/// unconditionally before checking `user == null`, so this has to be in
/// place for every test in this file, not only the ones that end up caring
/// about its answers.
class _FakeAuthService implements FirebaseAuthService {
  const _FakeAuthService();

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Regression coverage for the P1 audit finding: onboarding runs entirely
/// before any session (Firebase or [LocalAuthSession]) exists, so the local
/// draft [RegistrationNotifier._snapshot] writes after every step is the
/// ONLY copy of a member's answers until Verify Mobile succeeds. Before this
/// fix, [SplashController.resolveInitialRoute] treated "no session" as
/// synonymous with "nothing to resume" and called `clearNavState()`
/// unconditionally — deleting that draft before anything ever read it, so an
/// app kill mid-onboarding (an Android background reclaim, not a deliberate
/// exit) silently restarted the member from scratch.
///
/// These tests exercise [SplashController.resolveInitialRoute] end-to-end
/// for the "no session" branch — the only branch this fix touches.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `storageService` is a process-wide singleton with a `late` field —
  // init() can only run once per test process, matching the existing
  // convention in auth_session_test.dart. Each test sets exactly the keys it
  // needs rather than relying on a fresh store.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });

  setUp(() async {
    // A clean baseline before each test: language chosen (so the splash
    // doesn't short-circuit to the language screen), and no leftover nav
    // state from a previous test in this file.
    await storageService.setLanguage('en');
    await storageService.clearNavState();
  });

  ProviderContainer containerWithNoSession() {
    final container = ProviderContainer(
      overrides: [
        // authRepositoryProvider is read unconditionally near the top of
        // resolveInitialRoute (before the user == null check), and it watches
        // both of these — see the fakes' doc comments for why both are
        // needed even though this branch never calls a method on the
        // repository itself.
        firebaseAuthProvider.overrideWithValue(const _FakeFirebaseAuth()),
        firebaseAuthServiceProvider.overrideWithValue(const _FakeAuthService()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// A locally-saved draft in the exact shape [RegistrationNotifier._persist]
  /// writes via `saveNavState` — `route` is always
  /// [RouteNames.createProfileFor] and `profileFlowMode` is always
  /// `'create'`, regardless of which onboarding step actually wrote it (see
  /// that method's doc comment).
  Future<void> saveOnboardingSnapshot(ProfileDraft draft) {
    return storageService.saveNavState(
      route: RouteNames.createProfileFor,
      profileFlowMode: ProfileFlowMode.create.name,
      profileDraftJson: jsonEncode(draft.toJson()),
    );
  }

  group('Test 1 — draft survives restart', () {
    test('an unfinished draft is still on disk after a fresh app startup '
        'with no session, and resolves to an onboarding route (not wiped)',
        () async {
      final draft = const ProfileDraft(
        basicDetails: BasicDetails(
          profileCreatedFor: 'Myself',
          gender: 'Male',
        ),
      );
      await saveOnboardingSnapshot(draft);

      final container = containerWithNoSession();
      final route =
          await container.read(splashControllerProvider.notifier).resolveInitialRoute();

      // The bug: this used to always be RouteNames.registrationLanding,
      // because clearNavState() ran before anything read the snapshot.
      expect(route, isNot(RouteNames.registrationLanding));
      expect(route, RouteNames.onboardingNameDob);

      // The draft itself must still be on disk — proof it was read, not
      // deleted, by this resolution.
      expect(storageService.savedProfileDraftJson, isNotNull);
    });
  });

  group('Test 2 — resume the correct step', () {
    test('a draft with the first several sections answered resumes at the '
        'first unanswered one, not step 1', () async {
      final draft = const ProfileDraft(
        basicDetails: BasicDetails(
          profileCreatedFor: 'Myself',
          gender: 'Female',
          firstName: 'Priya',
          lastName: 'Nair',
          maritalStatus: 'Never Married',
        ),
        religionDetails: ReligionDetails(
          religion: 'Hindu',
          community: 'Nair',
        ),
        locationDetails: LocationDetails(
          country: 'India',
          state: 'Kerala',
          city: 'Kochi',
        ),
        physicalDetails: PhysicalDetails(height: '5\'4" (163 cm)'),
        educationDetails: EducationDetails(qualification: 'B.Sc'),
        // dob deliberately omitted below via basicDetails — see next case.
      );
      // dob has no simple const constructor path above; set it explicitly.
      final draftWithDob = draft.copyWith(
        basicDetails: draft.basicDetails.copyWith(dob: DateTime(1996, 3, 2)),
      );
      await saveOnboardingSnapshot(draftWithDob);

      final container = containerWithNoSession();
      final route =
          await container.read(splashControllerProvider.notifier).resolveInitialRoute();

      // Name/DOB, Religion, Basics (state/city), Marital and Education are
      // all answered — Income is the first thing still missing.
      expect(route, RouteNames.onboardingIncome);
    });

    test('a fully draft-answered signup (only Email+Mobile/OTP left, which '
        'writes no draft field) falls through cleanly rather than guessing',
        () async {
      final draft = ProfileDraft(
        basicDetails: BasicDetails(
          profileCreatedFor: 'Myself',
          gender: 'Male',
          firstName: 'Arjun',
          lastName: 'Menon',
          maritalStatus: 'Never Married',
          dob: DateTime(1994, 6, 18),
        ),
        religionDetails: const ReligionDetails(
          religion: 'Hindu',
          community: 'Menon',
        ),
        locationDetails: const LocationDetails(
          country: 'India',
          state: 'Kerala',
          city: 'Kochi',
        ),
        physicalDetails: const PhysicalDetails(height: '5\'9" (175 cm)'),
        educationDetails: const EducationDetails(
          qualification: 'B.E / B.Tech',
          annualIncome: '10 - 20 Lakhs',
        ),
        lifestyleDetails: const LifestyleDetails(aboutMe: 'A short bio.'),
      );
      await saveOnboardingSnapshot(draft);

      final container = containerWithNoSession();
      final route =
          await container.read(splashControllerProvider.notifier).resolveInitialRoute();

      // firstUnansweredOnboardingStep has nothing left to gate on — this
      // must never be treated as "let the member into the app" (there is no
      // session, so that would be an auth bypass) and must never crash.
      // Falling through to the landing screen is the documented, safe
      // outcome.
      expect(route, RouteNames.registrationLanding);
    });
  });

  group('Test 3 — completed registration clears the temporary draft', () {
    test('discardPersistedDraft removes the snapshot', () async {
      final draft = const ProfileDraft(
        basicDetails: BasicDetails(profileCreatedFor: 'Myself', gender: 'Male'),
      );
      await saveOnboardingSnapshot(draft);
      expect(storageService.savedProfileDraftJson, isNotNull);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(registrationProvider.notifier)
          .discardPersistedDraft();

      expect(storageService.savedProfileDraftJson, isNull);
    });

    test('once discarded, a fresh startup with no session lands on the '
        'registration landing screen rather than resuming stale progress',
        () async {
      final draft = const ProfileDraft(
        basicDetails: BasicDetails(profileCreatedFor: 'Myself', gender: 'Male'),
      );
      await saveOnboardingSnapshot(draft);

      final setupContainer = ProviderContainer();
      addTearDown(setupContainer.dispose);
      await setupContainer
          .read(registrationProvider.notifier)
          .discardPersistedDraft();

      final container = containerWithNoSession();
      final route =
          await container.read(splashControllerProvider.notifier).resolveInitialRoute();

      expect(route, RouteNames.registrationLanding);
    });
  });

  group('Test 4 — explicit reset clears the draft', () {
    test('startCreateMode discards the persisted snapshot', () async {
      final draft = const ProfileDraft(
        basicDetails: BasicDetails(profileCreatedFor: 'Myself', gender: 'Male'),
      );
      await saveOnboardingSnapshot(draft);
      expect(storageService.savedProfileDraftJson, isNotNull);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(registrationProvider.notifier).startCreateMode();

      // discardPersistedDraft is fire-and-forget (unawaited) inside
      // startCreateMode — pump once so the microtask actually runs.
      await Future<void>.delayed(Duration.zero);

      expect(storageService.savedProfileDraftJson, isNull);
      expect(
        container.read(registrationProvider),
        const ProfileDraft(),
        reason: 'the in-memory draft resets synchronously either way',
      );
    });
  });

  group('Test 5 — corrupt draft', () {
    test('invalid JSON on disk does not crash startup and is discarded '
        'cleanly, landing on the registration landing screen', () async {
      await storageService.saveNavState(
        route: RouteNames.createProfileFor,
        profileFlowMode: ProfileFlowMode.create.name,
        profileDraftJson: '{not valid json',
      );

      final container = containerWithNoSession();

      // Must not throw.
      final route =
          await container.read(splashControllerProvider.notifier).resolveInitialRoute();

      expect(route, RouteNames.registrationLanding);
    });

    test('a draft-shaped value that is not a JSON object also fails safely',
        () async {
      await storageService.saveNavState(
        route: RouteNames.createProfileFor,
        profileFlowMode: ProfileFlowMode.create.name,
        profileDraftJson: '"just a string"',
      );

      final container = containerWithNoSession();
      final route =
          await container.read(splashControllerProvider.notifier).resolveInitialRoute();

      expect(route, RouteNames.registrationLanding);
    });

    test('no snapshot at all resolves the same clean way', () async {
      // clearNavState() already ran in setUp — nothing to save.
      final container = containerWithNoSession();
      final route =
          await container.read(splashControllerProvider.notifier).resolveInitialRoute();

      expect(route, RouteNames.registrationLanding);
    });
  });

  group('Test 7 — no accidental auth bypass', () {
    test('a restored pre-session draft never resolves to Discover or any '
        'other protected route — only onboarding routes or the landing '
        'screen', () async {
      final complete = ProfileDraft(
        basicDetails: BasicDetails(
          profileCreatedFor: 'Myself',
          gender: 'Female',
          firstName: 'Divya',
          lastName: 'Raman',
          maritalStatus: 'Never Married',
          dob: DateTime(1998, 1, 1),
        ),
        religionDetails: const ReligionDetails(
          religion: 'Hindu',
          community: 'Iyer',
        ),
        locationDetails: const LocationDetails(
          country: 'India',
          state: 'Tamil Nadu',
          city: 'Chennai',
        ),
        physicalDetails: const PhysicalDetails(height: '5\'5" (165 cm)'),
        educationDetails: const EducationDetails(
          qualification: 'B.Com',
          annualIncome: '5 - 10 Lakhs',
        ),
        lifestyleDetails: const LifestyleDetails(aboutMe: 'Hello there.'),
      );
      await saveOnboardingSnapshot(complete);

      final container = containerWithNoSession();
      final route =
          await container.read(splashControllerProvider.notifier).resolveInitialRoute();

      // Even a fully-answered draft-backed chain must not be treated as
      // "signed in" — there is no session, Firebase or local, so the only
      // legitimate destinations are an onboarding step or the landing
      // screen. Discover (and every other protected route) must be
      // unreachable from this path.
      expect(route, isNot(RouteNames.discover));
      expect(RouteNames.publicRoutes.contains(route), isTrue,
          reason: 'every destination this path can return must be public');
    });

    test('restoring the draft never marks onboarding completed or opens a '
        'local session', () async {
      final draft = const ProfileDraft(
        basicDetails: BasicDetails(profileCreatedFor: 'Myself', gender: 'Male'),
      );
      await saveOnboardingSnapshot(draft);

      final container = containerWithNoSession();
      await container.read(splashControllerProvider.notifier).resolveInitialRoute();

      expect(storageService.onboardingCompleted, isFalse);
      expect(storageService.localSessionIdentifier, isNull);
    });
  });

  group('Test 6 — authenticated user with no unfinished draft', () {
    test('an active LocalAuthSession still goes straight to Discover, '
        'unaffected by this change', () async {
      await storageService.setLocalSession(
        identifier: '+911234567890',
        method: 'mobileOtp',
      );
      addTearDown(() => storageService.clearLocalSession());

      final container = containerWithNoSession();
      final route =
          await container.read(splashControllerProvider.notifier).resolveInitialRoute();

      expect(route, RouteNames.discover);
    });
  });
}
