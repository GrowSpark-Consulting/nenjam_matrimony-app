import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/data/models/auth_user.dart';
import 'package:nenjam_matrimony/features/authentication/data/repositories/auth_repository_impl.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/google_auth_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/controllers/login_controller.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
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
          .signIn();

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
          .signIn();

      expect(result.success, isTrue);
      expect(result.needsVerification, isTrue);
    });

    test('cancellation is not an error and carries no message', () async {
      final container = _containerReturning(
        () async => throw const GoogleSignInCancelled(),
      );

      final result = await container
          .read(googleSignInControllerProvider.notifier)
          .signIn();

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
          .signIn();

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
          .signIn();

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
          .signIn();

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
      await container.read(googleSignInControllerProvider.notifier).signIn();

      expect(loadingDuringCall, isTrue);
      expect(container.read(googleSignInControllerProvider), isFalse);
    });

    test('loading is cleared even when sign-in throws', () async {
      final container = _containerReturning(
        () async => throw StateError('boom'),
      );

      await container.read(googleSignInControllerProvider.notifier).signIn();

      expect(container.read(googleSignInControllerProvider), isFalse);
    });
  });
}
