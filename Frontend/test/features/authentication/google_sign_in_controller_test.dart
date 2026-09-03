import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/data/models/auth_user.dart';
import 'package:nenjam_matrimony/features/authentication/data/repositories/auth_repository_impl.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/google_auth_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/controllers/login_controller.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/onboarding_forms.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Stands in for the real repository. `noSuchMethod` forwarding lets this
/// implement only the one member under test without needing a live
/// FirebaseAuth (which a unit test has no way to construct).
class _FakeAuthRepository implements FirebaseAuthRepository {
  _FakeAuthRepository(this._onGoogleLogin);

  final Future<AuthUser> Function() _onGoogleLogin;

  @override
  Future<AuthUser> loginWithGoogle() => _onGoogleLogin();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

ProviderContainer _containerReturning(Future<AuthUser> Function() onLogin) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository(onLogin)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

const _googleUser = AuthUser(
  uid: 'uid-1',
  username: 'Arjun Krishnan',
  email: 'arjun@gmail.com',
  emailVerified: true, // Google vouches for the address
);

void main() {
  group('GoogleSignInController', () {
    test('success routes straight in — Google emails need no verification',
        () async {
      final container = _containerReturning(() async => _googleUser);

      final result = await container
          .read(googleSignInControllerProvider.notifier)
          .signIn(intent: GoogleAuthIntent.login);

      expect(result.success, isTrue);
      expect(result.cancelled, isFalse);
      expect(result.errorMessage, isNull);
      expect(result.user?.uid, 'uid-1');
      // False here is what sends the user to Discover rather than into the
      // email-verification flow.
      expect(result.needsVerification, isFalse);
    });

    test('an unverified account is still routed to verification', () async {
      final container = _containerReturning(
        () async => const AuthUser(uid: 'uid-2', emailVerified: false),
      );

      final result = await container
          .read(googleSignInControllerProvider.notifier)
          .signIn(intent: GoogleAuthIntent.login);

      expect(result.success, isTrue);
      expect(result.needsVerification, isTrue);
    });

    test('cancellation is not an error and carries no message', () async {
      final container = _containerReturning(
        () async => throw const GoogleSignInCancelled(),
      );

      final result = await container
          .read(googleSignInControllerProvider.notifier)
          .signIn(intent: GoogleAuthIntent.login);

      expect(result.cancelled, isTrue);
      expect(result.success, isFalse);
      // The page keys off this being null to stay silent.
      expect(result.errorMessage, isNull);
    });

    test('a FirebaseAuthException surfaces a mapped, non-raw message',
        () async {
      final container = _containerReturning(
        () async => throw FirebaseAuthException(
          code: 'account-exists-with-different-credential',
          message: 'raw firebase text that must not reach the user',
        ),
      );

      final result = await container
          .read(googleSignInControllerProvider.notifier)
          .signIn(intent: GoogleAuthIntent.login);

      expect(result.success, isFalse);
      expect(result.cancelled, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(
        result.errorMessage,
        isNot(contains('raw firebase text')),
        reason: 'AuthErrorMapper must not leak raw Firebase strings',
      );
    });

    // Regression guard: google_sign_in_android reports hard Credential
    // Manager failures with code `canceled`. Swallowing those silently made
    // the button appear dead on a real device ("[16] Account reauth
    // failed."). Only a description-free cancel is a real user dismissal.
    test('a play-services failure disguised as `canceled` is NOT silent',
        () async {
      final container = _containerReturning(
        () async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: '[16] Account reauth failed.',
        ),
      );

      final result = await container
          .read(googleSignInControllerProvider.notifier)
          .signIn(intent: GoogleAuthIntent.login);

      expect(result.cancelled, isFalse,
          reason: 'a bracketed play-services status is a failure, not a '
              'user dismissal');
      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull,
          reason: 'the user must be told something went wrong');
    });

    test('an arbitrary exception falls back to the generic message', () async {
      final container = _containerReturning(
        () async => throw StateError('boom'),
      );

      final result = await container
          .read(googleSignInControllerProvider.notifier)
          .signIn(intent: GoogleAuthIntent.login);

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage, isNot(contains('boom')));
    });

    test('loading flag is raised during the call and cleared after', () async {
      var loadingDuringCall = false;
      // `late` so the callback can read the container it is installed into.
      late final ProviderContainer container;
      container = _containerReturning(() async {
        loadingDuringCall = container.read(googleSignInControllerProvider);
        return _googleUser;
      });

      expect(container.read(googleSignInControllerProvider), isFalse);
      await container.read(googleSignInControllerProvider.notifier).signIn(intent: GoogleAuthIntent.login);

      expect(loadingDuringCall, isTrue);
      expect(container.read(googleSignInControllerProvider), isFalse);
    });

    test('loading is cleared even when sign-in throws', () async {
      final container = _containerReturning(
        () async => throw StateError('boom'),
      );

      await container.read(googleSignInControllerProvider.notifier).signIn(intent: GoogleAuthIntent.login);

      expect(container.read(googleSignInControllerProvider), isFalse);
    });
  });

  // ─── Intent ──────────────────────────────────────────────────────────
  //
  // The Google credential exchange is one implementation for both buttons —
  // there is only one, and duplicating it would be two things to keep right.
  // What the intent changes is what happens around it.
  group('GoogleAuthIntent', () {
    /// A draft carrying answers, as a previous session would have left it.
    void seedStaleDraft(ProviderContainer container) {
      final notifier = container.read(registrationProvider.notifier);
      notifier.applyProfileFor(
        const ProfileForForm(profileCreatedFor: 'Son', gender: 'Female'),
      );
    }

    test('signup starts CREATE mode, so onboarding never begins on a stale '
        'draft', () async {
      final container = _containerReturning(() async => _googleUser);
      seedStaleDraft(container);
      expect(
        container.read(registrationProvider).basicDetails.profileCreatedFor,
        'Son',
      );

      await container
          .read(googleSignInControllerProvider.notifier)
          .signIn(intent: GoogleAuthIntent.signup);

      // The regression this fixes: Google was the one sign-up button of the
      // three that never called startCreateMode(), so a member who abandoned
      // a signup and started a new one carried the old answers forward.
      final draft = container.read(registrationProvider);
      expect(draft.basicDetails.profileCreatedFor, isEmpty);
      expect(draft.basicDetails.gender, isEmpty);
      expect(
        container.read(profileFlowModeProvider),
        ProfileFlowMode.create,
        reason: 'a Google signup is a CREATE-mode session, like the other two',
      );
    });

    test('login leaves the draft alone', () async {
      final container = _containerReturning(() async => _googleUser);
      seedStaleDraft(container);

      await container
          .read(googleSignInControllerProvider.notifier)
          .signIn(intent: GoogleAuthIntent.login);

      // A login must not clear a registration in progress: a member part-way
      // through signup who signs in again resumes, and PostAuthDestination
      // rehydrates from the backend on top of whatever is here.
      final draft = container.read(registrationProvider);
      expect(draft.basicDetails.profileCreatedFor, 'Son');
      expect(draft.basicDetails.gender, 'Female');
    });

    test('both intents authenticate through the same single Google call',
        () async {
      // No second authentication path — the defect was that the two buttons
      // were indistinguishable, not that they shared an implementation.
      var calls = 0;
      final container = _containerReturning(() async {
        calls++;
        return _googleUser;
      });

      final login = await container
          .read(googleSignInControllerProvider.notifier)
          .signIn(intent: GoogleAuthIntent.login);
      final signup = await container
          .read(googleSignInControllerProvider.notifier)
          .signIn(intent: GoogleAuthIntent.signup);

      expect(calls, 2);
      expect(login.success, isTrue);
      expect(signup.success, isTrue);
      expect(login.user?.uid, signup.user?.uid);
    });

    test('a cancelled signup does not reset the draft', () async {
      final container = _containerReturning(
        () async => throw const GoogleSignInCancelled(),
      );
      seedStaleDraft(container);

      final result = await container
          .read(googleSignInControllerProvider.notifier)
          .signIn(intent: GoogleAuthIntent.signup);

      // Backing out of the account picker is not the start of a signup, so
      // it must not cost a member the answers they already gave.
      expect(result.cancelled, isTrue);
      expect(
        container.read(registrationProvider).basicDetails.profileCreatedFor,
        'Son',
      );
    });
  });
}
