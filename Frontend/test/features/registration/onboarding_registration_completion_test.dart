import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/dummy_otp_session.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/profile/data/repositories/api_profile_repository.dart';
import 'package:nenjam_matrimony/features/profile/domain/models/profile.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_verify_mobile_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/features/verification/domain/models/face_verification.dart';
import 'package:nenjam_matrimony/features/verification/domain/repositories/face_verification_repository.dart';
import 'package:nenjam_matrimony/features/verification/presentation/providers/face_verification_providers.dart';

import 'onboarding_test_support.dart';

/// The end of onboarding: **save → finalize → mark complete → Discover**, and
/// nothing after a failure.
///
/// Before this, `onboardingCompleted` was written before anything was sent,
/// the save swallowed its own errors, finalize ran "quietly", and the member
/// was navigated to Discover regardless. One rejected section let them in with
/// an unfinalized profile: hidden from every feed, shown an empty one of their
/// own, and sent back to an earlier step on their next login.
///
/// Failures are injected as the same [ApiException] the real repository
/// throws — a 400 from a rejected section, a 500 from finalize — so the page
/// is exercised against the errors it will actually see.
/// The backend's answer while `FACE_VERIFICATION_ENABLED=false`: the feature
/// is not offered at all, so it cannot be a precondition for entry.
const _notAvailable = FaceVerificationState(
  status: FaceVerificationStatus.unverified,
  verifiedAt: null,
  canStart: false,
  blockedReason: FaceBlockedReason.notAvailable,
  attemptsRemainingToday: 0,
  retryAfter: null,
);

/// Feature on, member has never verified — the gate must hold.
const _verificationRequired = FaceVerificationState(
  status: FaceVerificationStatus.unverified,
  verifiedAt: null,
  canStart: true,
  blockedReason: null,
  attemptsRemainingToday: 3,
  retryAfter: null,
);

/// Feature on, already verified against the current primary photo.
const _verified = FaceVerificationState(
  status: FaceVerificationStatus.verified,
  verifiedAt: null,
  canStart: false,
  blockedReason: FaceBlockedReason.alreadyVerified,
  attemptsRemainingToday: 3,
  retryAfter: null,
);

void main() {
  const failureMessage =
      'Your number is verified, but we could not save your profile. '
      'Check your connection and tap Retry.';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });

  setUp(() async {
    await storageService.clearLocalSession();
    await storageService.setOnboardingCompleted(false);
    await storageService.setPendingPhone('+919876543210');
    await storageService.setPendingEmail('member@example.com');
  });

  GoRouter buildRouter() => GoRouter(
        initialLocation: RouteNames.onboardingVerifyMobile,
        routes: [
          GoRoute(
            path: RouteNames.onboardingVerifyMobile,
            builder: (context, state) => const OnboardingVerifyMobilePage(),
          ),
          GoRoute(
            path: RouteNames.discover,
            builder: (context, state) =>
                const Scaffold(body: Text('discover-reached')),
          ),
          GoRoute(
            path: RouteNames.faceVerification,
            builder: (context, state) =>
                const Scaffold(body: Text('face-verification-reached')),
          ),
        ],
      );

  /// Signed in, because a successful exchange leaves a real Firebase user and
  /// the flush only sends with a session — see `RegistrationNotifier
  /// ._hasSession`. Without it the flush is a no-op and nothing here would be
  /// exercised.
  /// Finishing onboarding now routes through [PostAuthDestination] rather
  /// than straight to Discover (see the comment at that call site): once
  /// `onboardingCompleted` is true the router's own guard stops asking the
  /// resolver, so this screen is the only place left that can run the face
  /// verification gate for a brand-new member. That makes the resolver's two
  /// backend reads — the finalized-profile check and `GET /verification/face`
  /// — part of this flow, so both are faked here.
  ///
  /// The defaults describe the real world today: the member's profile exists
  /// (finalize just wrote it) and face verification is switched off backend
  /// side, which is the `NOT_AVAILABLE` pass-through. Every pre-existing test
  /// below therefore still ends at Discover exactly as it did.
  ProviderContainer containerWith(
    _ControllableRepository repository,
    _RecordingStarter starter, {
    FaceVerificationState faceVerification = _notAvailable,
  }) {
    return ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
        dummyOtpSessionStarterProvider.overrideWithValue(starter),
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
        profileRepositoryProvider.overrideWithValue(_FinalizedProfileRepository()),
        faceVerificationRepositoryProvider
            .overrideWithValue(_FakeFaceVerificationRepository(faceVerification)),
      ],
    );
  }

  Future<void> pumpVerifyStep(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
  }

  /// [NmOtpInput] submits itself on the last digit — the same interaction a
  /// member performs.
  Future<void> enterCode(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.pumpAndSettle();
  }

  Future<void> tapRetry(WidgetTester tester) async {
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
  }

  // ─── Test 1 — Successful registration ─────────────────────────────────

  testWidgets('every save and finalize succeed: onboarding completes, then '
      'Discover', (tester) async {
    final repository = _ControllableRepository();
    final starter = _RecordingStarter();
    final container = containerWith(repository, starter);
    addTearDown(container.dispose);

    await pumpVerifyStep(tester, container);
    await enterCode(tester);

    // Every section the profile row needs reached the backend, and the one
    // that materializes ran last.
    expect(
      repository.savedSections,
      containsAll(<String>[
        'basicDetails',
        'religionDetails',
        'languageDetails',
        'locationDetails',
        'physicalDetails',
        'educationDetails',
        'lifestyleDetails',
      ]),
    );
    expect(repository.savedSections.last, 'lifestyleDetails');
    expect(repository.finalizeCalls, 1);

    expect(storageService.onboardingCompleted, isTrue);
    expect(storageService.pendingPhone, isNull);
    expect(find.text('discover-reached'), findsOneWidget);
  });

  // ─── Test 2 — Flush failure ───────────────────────────────────────────

  testWidgets('a rejected section stops everything: not complete, finalize '
      'never called, error shown, Retry offered', (tester) async {
    final repository = _ControllableRepository()..failReligionSave = true;
    final starter = _RecordingStarter();
    final container = containerWith(repository, starter);
    addTearDown(container.dispose);

    await pumpVerifyStep(tester, container);
    await enterCode(tester);

    // The failure stops the sequence where it happened. Everything after
    // religion — including the call that materializes the profile — was not
    // sent, and finalize was never reached.
    expect(repository.savedSections, isNot(contains('lifestyleDetails')));
    expect(repository.finalizeAttempts, 0);

    // Not complete, not let in.
    expect(storageService.onboardingCompleted, isFalse);
    expect(find.text('discover-reached'), findsNothing);

    // Told why, in words they can act on, with a way to try again.
    expect(find.text(failureMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Nothing lost: the number and the answers survive for the retry.
    expect(storageService.pendingPhone, '+919876543210');
  });

  // ─── Test 3 — Finalize failure ────────────────────────────────────────

  testWidgets('every save succeeds but finalize fails: still not complete, '
      'still not let in', (tester) async {
    final repository = _ControllableRepository()..failFinalize = true;
    final starter = _RecordingStarter();
    final container = containerWith(repository, starter);
    addTearDown(container.dispose);

    await pumpVerifyStep(tester, container);
    await enterCode(tester);

    // The saves all landed and finalize was genuinely attempted...
    expect(repository.savedSections, contains('lifestyleDetails'));
    expect(repository.finalizeAttempts, 1);
    expect(repository.finalizeCalls, 0);

    // ...but a finalize that failed is a registration that did not finish.
    expect(storageService.onboardingCompleted, isFalse);
    expect(find.text('discover-reached'), findsNothing);
    expect(find.text(failureMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(storageService.pendingPhone, '+919876543210');
  });

  // ─── Test 4 — Retry after failure ─────────────────────────────────────

  testWidgets('a retry after a failed save completes onboarding, without '
      'repeating the code or the session exchange', (tester) async {
    final repository = _ControllableRepository()..failReligionSave = true;
    final starter = _RecordingStarter();
    final container = containerWith(repository, starter);
    addTearDown(container.dispose);

    await pumpVerifyStep(tester, container);
    await enterCode(tester);

    // First attempt failed.
    expect(storageService.onboardingCompleted, isFalse);
    expect(find.text('Retry'), findsOneWidget);

    // The backend recovers; the member taps Retry.
    repository.failReligionSave = false;
    await tapRetry(tester);

    expect(storageService.onboardingCompleted, isTrue);
    expect(repository.finalizeCalls, 1);
    expect(find.text('discover-reached'), findsOneWidget);

    // The account was provisioned once. Retry resumes from the save; it does
    // not ask the backend to mint a second session for the same number.
    expect(starter.phones, ['+919876543210']);
  });

  testWidgets('a retry after a failed finalize completes onboarding', (
    tester,
  ) async {
    final repository = _ControllableRepository()..failFinalize = true;
    final starter = _RecordingStarter();
    final container = containerWith(repository, starter);
    addTearDown(container.dispose);

    await pumpVerifyStep(tester, container);
    await enterCode(tester);
    expect(storageService.onboardingCompleted, isFalse);

    repository.failFinalize = false;
    await tapRetry(tester);

    expect(storageService.onboardingCompleted, isTrue);
    expect(repository.finalizeAttempts, 2);
    expect(repository.finalizeCalls, 1);
    expect(find.text('discover-reached'), findsOneWidget);
    expect(starter.phones, hasLength(1));
  });

  // ─── Test 5 — No silent catch ─────────────────────────────────────────

  testWidgets('a failed request can never leave the same state as success', (
    tester,
  ) async {
    // A build that wrote the flag early may have left it set. That stale
    // "complete" must not survive a failed attempt — otherwise the router's
    // local bridge would still treat this member as onboarded.
    await storageService.setOnboardingCompleted(true);

    final repository = _ControllableRepository()..failReligionSave = true;
    final starter = _RecordingStarter();
    final container = containerWith(repository, starter);
    addTearDown(container.dispose);

    await pumpVerifyStep(tester, container);
    await enterCode(tester);

    // Every observable a successful registration sets, a failed one must not.
    expect(storageService.onboardingCompleted, isFalse,
        reason: 'the flag must describe the attempt that just failed');
    expect(find.text('discover-reached'), findsNothing,
        reason: 'a failed registration must not navigate to Discover');
    expect(repository.finalizeCalls, 0,
        reason: 'finalize must not succeed after a failed save');
    expect(storageService.pendingPhone, isNotNull,
        reason: 'the number is only cleared on success');
    expect(find.text(failureMessage), findsOneWidget,
        reason: 'the failure must be surfaced, not swallowed');
  });

  // ─── Test 6 — The face verification gate ──────────────────────────────
  //
  // Finishing onboarding is the first moment the gate can run for a new
  // member, and for a while it was the one moment it could not: this screen
  // navigated straight to Discover, and `setOnboardingCompleted(true)` (a few
  // lines earlier) had already switched off the router guard's own call to
  // PostAuthDestination — the only other place the gate lives. A member who
  // owed a verification walked past it into Discover.

  testWidgets('verification required: the new member is sent to Face '
      'Verification, not Discover', (tester) async {
    final repository = _ControllableRepository();
    final starter = _RecordingStarter();
    final container = containerWith(
      repository,
      starter,
      faceVerification: _verificationRequired,
    );
    addTearDown(container.dispose);

    await pumpVerifyStep(tester, container);
    await enterCode(tester);

    // Registration itself genuinely finished — this is a gate, not a failure.
    expect(repository.finalizeCalls, 1);
    expect(storageService.onboardingCompleted, isTrue);
    expect(find.text(failureMessage), findsNothing);

    expect(find.text('face-verification-reached'), findsOneWidget);
    expect(find.text('discover-reached'), findsNothing,
        reason: 'an unverified member must not reach Discover');
  });

  testWidgets('already verified: the new member goes straight to Discover', (
    tester,
  ) async {
    final repository = _ControllableRepository();
    final starter = _RecordingStarter();
    final container =
        containerWith(repository, starter, faceVerification: _verified);
    addTearDown(container.dispose);

    await pumpVerifyStep(tester, container);
    await enterCode(tester);

    expect(find.text('discover-reached'), findsOneWidget);
    expect(find.text('face-verification-reached'), findsNothing);
  });

  testWidgets('NOT_AVAILABLE: the feature being off never blocks entry', (
    tester,
  ) async {
    final repository = _ControllableRepository();
    final starter = _RecordingStarter();
    final container =
        containerWith(repository, starter, faceVerification: _notAvailable);
    addTearDown(container.dispose);

    await pumpVerifyStep(tester, container);
    await enterCode(tester);

    // The pass-through that keeps today's builds working: the backend has not
    // offered verification, so it cannot be owed. Deliberately NOT the same
    // thing as being verified — see FaceVerificationState.satisfiesEntryGate.
    expect(find.text('discover-reached'), findsOneWidget);
    expect(find.text('face-verification-reached'), findsNothing);
  });

  testWidgets('REVOKED: a member whose primary photo changed must re-verify', (
    tester,
  ) async {
    final repository = _ControllableRepository();
    final starter = _RecordingStarter();
    final container = containerWith(
      repository,
      starter,
      faceVerification: const FaceVerificationState(
        status: FaceVerificationStatus.revoked,
        verifiedAt: null,
        canStart: true,
        blockedReason: null,
        attemptsRemainingToday: 3,
        retryAfter: null,
      ),
    );
    addTearDown(container.dispose);

    await pumpVerifyStep(tester, container);
    await enterCode(tester);

    expect(find.text('face-verification-reached'), findsOneWidget);
    expect(find.text('discover-reached'), findsNothing);
  });

  test('the flush throws the original error instead of swallowing it', () async {
    final repository = _ControllableRepository()..failReligionSave = true;
    final container = containerWith(repository, _RecordingStarter());
    addTearDown(container.dispose);

    // The exact error the repository raised reaches the caller — not a
    // generic wrapper, and not a normal return.
    await expectLater(
      container.read(registrationProvider.notifier).flushOnboardingToBackend(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('religionCode')),
      ),
    );

    // It stopped at the failure: nothing after religion was sent.
    expect(repository.savedSections, ['basicDetails']);
  });
}

/// [RecordingRegistrationRepository] with failures that can be switched off
/// mid-test, which is what a retry needs. The shared recorder's own flags are
/// fixed at construction; subclassing here leaves every other test untouched.
class _ControllableRepository extends RecordingRegistrationRepository {
  bool failReligionSave = false;
  bool failFinalize = false;

  /// Every finalize request, including ones that failed. The inherited
  /// `finalizeCalls` counts successes only.
  int finalizeAttempts = 0;

  @override
  Future<void> updateReligionDetails(
    ReligionDetails details, {
    bool skipMaterialize = false,
  }) async {
    if (failReligionSave) {
      // What the backend actually answered before P0-1, verbatim.
      throw ApiException(400, 'property religionCode should not exist');
    }
    return super.updateReligionDetails(details, skipMaterialize: skipMaterialize);
  }

  @override
  Future<Map<String, dynamic>> finalizeProfile() async {
    finalizeAttempts++;
    if (failFinalize) throw ApiException(500, 'Internal server error');
    return super.finalizeProfile();
  }
}

/// Stands in for `POST /auth/dummy-otp/session`, recording each number it was
/// asked to provision so a test can prove a retry did not ask twice.
class _RecordingStarter implements DummyOtpSessionStarter {
  final List<String> phones = <String>[];

  @override
  Future<String> start({required String phoneE164, String? email}) async {
    phones.add(phoneE164);
    return 'firebase-uid-1';
  }
}

/// `GET /profiles/me` answering with a row, which is what finalize has just
/// written by the time the resolver asks. Returning one (rather than the 404
/// a half-registered member gets) is what makes [PostAuthDestination] take its
/// finalized-profile branch, where the face verification gate sits.
class _FinalizedProfileRepository implements ApiProfileRepository {
  @override
  Future<Profile> getMyProfile() async => Profile.fromJson(const {
        'firstName': 'Member',
        'currentState': 'Tamil Nadu',
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `GET /verification/face`. Only the read matters here: the gate never starts
/// a session or completes an attempt, so both of those throw rather than
/// return a fabricated result.
class _FakeFaceVerificationRepository implements FaceVerificationRepository {
  _FakeFaceVerificationRepository(this._state);

  final FaceVerificationState _state;

  @override
  Future<FaceVerificationState> getState() async => _state;

  @override
  Future<LivenessSessionTicket> startSession({required bool consent}) =>
      throw UnimplementedError();

  @override
  Future<FaceVerificationResult> complete({
    required String attemptId,
    ClientLivenessOutcome? clientOutcome,
    String? clientErrorCode,
  }) =>
      throw UnimplementedError();
}
