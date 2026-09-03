import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nenjam_matrimony/features/authentication/data/models/auth_user.dart';
import 'package:nenjam_matrimony/features/authentication/data/repositories/auth_repository_impl.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/otp_verifier.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/controllers/phone_auth_controller.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';

/// The production OTP path: [FirebasePhoneOtpVerifier].
///
/// Exercised directly rather than through [otpVerifierProvider], because
/// `kDebugMode` is a compile-time constant and the test runner is always a
/// debug build — going through the provider could only ever reach the mock.
/// Constructing the real verifier here is what makes the release behaviour
/// testable at all, and every assertion below holds regardless of build mode.
///
/// The property that matters most: **no branch returns `true` unless Firebase
/// accepted the credential.** Wrong codes, expired sessions, a send that never
/// produced a verification id, and outright failures all answer `false`.
void main() {
  group('FirebasePhoneOtpVerifier', () {
    test('asks for a six-digit code, the shape Firebase sends', () {
      // The onboarding screen reads this for both its input boxes and its
      // submit gate, so the UI follows without a screen change. The mock's
      // four digits would silently truncate a real SMS code.
      final h = _harness();
      expect(h.verifier.codeLength, 6);
    });

    test('sending delegates to the existing phone-auth controller', () async {
      // Not a second SMS implementation: the resend token, the 60s countdown
      // and Android auto-retrieval all stay in PhoneAuthController.
      final h = _harness();

      await h.verifier.send('+919876543210');

      expect(h.controller.sentTo, ['+919876543210']);
    });

    test('a correct code signs a session-less member in', () async {
      // The common signup path — onboarding collects the whole profile before
      // asking for any credential, so there is no account to link to yet.
      final h = _harness(verificationId: 'vid-1');

      expect(await h.verifier.verify('123456'), isTrue);

      expect(h.repository.loginCalls, [('vid-1', '123456')]);
      expect(h.repository.linkCalls, isEmpty);
    });

    test('a correct code links onto an account that already exists', () async {
      // Google/email signup reaches this step already signed in. Linking is
      // what stops one member becoming two accounts.
      final h = _harness(verificationId: 'vid-1', signedIn: true);

      expect(await h.verifier.verify('123456'), isTrue);

      expect(h.repository.linkCalls, [('vid-1', '123456')]);
      expect(h.repository.loginCalls, isEmpty);
    });

    test('a number already on another account is not reported as verified',
        () async {
      // The link genuinely did not happen — the number belongs to a different
      // Firebase account — so `currentUser.phoneNumber` stays null. Answering
      // `true` here advanced the member to Discover, where the "no mobile
      // number" gate bounced them back to the Email + Mobile step to try the
      // same number and be waved through again: a soft lock with no
      // explanation. It must read as a failure, with a reason.
      final h = _harness(
        verificationId: 'vid-1',
        signedIn: true,
        failWith: FirebaseAuthException(code: 'credential-already-in-use'),
      );

      expect(await h.verifier.verify('123456'), isFalse);
      expect(
        h.container.read(phoneAuthControllerProvider).errorMessage,
        isNotNull,
        reason: 'the member has to be told why the number was refused',
      );
    });

    test('an incorrect code is rejected, not raised as an error', () async {
      final h = _harness(
        verificationId: 'vid-1',
        failWith: FirebaseAuthException(code: 'invalid-verification-code'),
      );

      expect(await h.verifier.verify('000000'), isFalse);
    });

    test('an expired code is rejected', () async {
      final h = _harness(
        verificationId: 'vid-1',
        failWith: FirebaseAuthException(code: 'session-expired'),
      );

      expect(await h.verifier.verify('123456'), isFalse);
    });

    test('a stale verification id is rejected', () async {
      final h = _harness(
        verificationId: 'vid-1',
        failWith: FirebaseAuthException(code: 'invalid-verification-id'),
      );

      expect(await h.verifier.verify('123456'), isFalse);
    });

    test('never approves when no SMS session was established', () async {
      // Send failed, or Firebase rejected the number, or phone auth is not
      // enabled on the project. There is nothing to verify against, and the
      // repository must not be asked.
      final h = _harness();

      expect(await h.verifier.verify('123456'), isFalse);

      expect(h.repository.loginCalls, isEmpty);
      expect(h.repository.linkCalls, isEmpty);
    });

    test('a network failure fails closed and records why', () async {
      // Still `false` — the screen has no throwing path, and an exception
      // escaping the verifier would crash it — but the reason is kept on the
      // shared phone-auth state rather than discarded.
      final h = _harness(
        verificationId: 'vid-1',
        failWith: FirebaseAuthException(code: 'network-request-failed'),
      );

      expect(await h.verifier.verify('123456'), isFalse);
      expect(h.container.read(phoneAuthControllerProvider).errorMessage,
          isNotNull);
    });

    test('an unexpected error fails closed rather than throwing', () async {
      final h = _harness(
        verificationId: 'vid-1',
        failWith: StateError('something else entirely'),
      );

      expect(await h.verifier.verify('123456'), isFalse);
    });

    test('phone auth disabled on the project cannot authenticate', () async {
      // Deployment misconfiguration, not a code path: verifyPhoneNumber fails,
      // so no verification id is ever produced and every code is refused.
      final h = _harness(
        failWith: FirebaseAuthException(code: 'operation-not-allowed'),
      );

      for (final code in ['123456', '000000', '999999', '']) {
        expect(await h.verifier.verify(code), isFalse);
      }
    });
  });

  group('otpVerifierProvider', () {
    test('selects mock or real from the one switch, and never both', () {
      // `kDebugMode` cannot be flipped from inside a test, but the provider's
      // condition is `kDebugMode && !USE_REAL_OTP` — so bypassing the second
      // half reaches the SAME branch a release build takes. Running this suite
      // twice, with and without the define, therefore covers both outcomes of
      // a compile-time constant:
      //
      //   flutter test                                  → mock  (debug default)
      //   flutter test --dart-define=USE_REAL_OTP=true  → real  (release path)
      const useReal = bool.fromEnvironment('USE_REAL_OTP');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final verifier = container.read(otpVerifierProvider);

      if (useReal) {
        expect(
          verifier,
          isA<FirebasePhoneOtpVerifier>(),
          reason: 'the release path must be the real Firebase verifier',
        );
        expect(
          verifier,
          isNot(isA<MockOtpVerifier>()),
          reason: 'the permissive mock must be unreachable in release',
        );
      } else {
        expect(verifier, isA<MockOtpVerifier>());
        expect(verifier, isNot(isA<FirebasePhoneOtpVerifier>()));
      }
    });

    test('no verifier accepts a code without Firebase except the mock', () {
      // Guards against a future third implementation quietly becoming the
      // production default: the only permissive verifier in the file is the
      // one the provider gates behind kDebugMode.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const useReal = bool.fromEnvironment('USE_REAL_OTP');
      expect(
        container.read(otpVerifierProvider) is MockOtpVerifier,
        !useReal,
      );
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Harness
// ─────────────────────────────────────────────────────────────────────────────

class _Harness {
  _Harness(this.container, this.verifier, this.controller, this.repository);

  final ProviderContainer container;
  final OtpVerifier verifier;
  final _FakePhoneAuthController controller;
  final _FakeAuthRepository repository;
}

/// Builds the real verifier over fakes.
///
/// [verificationId] null models "no SMS session yet"; [signedIn] models the
/// Google/email signup arriving with an account already; [failWith] is what
/// the repository throws when the code is submitted.
_Harness _harness({
  String? verificationId,
  bool signedIn = false,
  Object? failWith,
}) {
  final controller = _FakePhoneAuthController(
    PhoneAuthState(
      status: verificationId == null
          ? PhoneAuthStatus.idle
          : PhoneAuthStatus.codeSent,
      verificationId: verificationId,
    ),
  );
  final repository = _FakeAuthRepository(failWith: failWith);

  final container = ProviderContainer(
    overrides: [
      phoneAuthControllerProvider.overrideWith(() => controller),
      authRepositoryProvider.overrideWithValue(repository),
      firebaseAuthServiceProvider.overrideWithValue(
        _FakeFirebaseAuthService(signedIn ? _FakeUser() : null),
      ),
      // The real verifier, regardless of build mode — the whole point.
      _realVerifierProvider,
    ],
  );
  addTearDown(container.dispose);

  return _Harness(
    container,
    container.read(otpVerifierProvider),
    controller,
    repository,
  );
}

/// Forces [otpVerifierProvider] to the production implementation so the
/// release path is reachable from a debug test runner.
final _realVerifierProvider = otpVerifierProvider.overrideWith(
  (ref) => FirebasePhoneOtpVerifier(ref),
);

class _FakePhoneAuthController extends PhoneAuthController {
  _FakePhoneAuthController(this._initial);

  final PhoneAuthState _initial;
  final List<String> sentTo = [];

  // Overridden so the real build()'s ref.onDispose timer wiring is skipped.
  @override
  PhoneAuthState build() => _initial;

  @override
  Future<void> sendCode(String phoneE164) async => sentTo.add(phoneE164);
}

/// `noSuchMethod` forwarding, as in google_sign_in_controller_test.dart: only
/// the members under test are implemented, so no live FirebaseAuth is needed.
class _FakeAuthRepository implements FirebaseAuthRepository {
  _FakeAuthRepository({this.failWith});

  final Object? failWith;
  final List<(String, String)> loginCalls = [];
  final List<(String, String)> linkCalls = [];

  @override
  Future<AuthUser> loginWithPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) async {
    if (failWith != null) throw failWith!;
    loginCalls.add((verificationId, smsCode));
    return const AuthUser(uid: 'uid-1', username: '', email: '');
  }

  @override
  Future<void> confirmPhoneForSignup({
    required String verificationId,
    required String smsCode,
  }) async {
    if (failWith != null) throw failWith!;
    linkCalls.add((verificationId, smsCode));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirebaseAuthService implements FirebaseAuthService {
  _FakeFirebaseAuthService(this._currentUser);

  final User? _currentUser;

  @override
  User? get currentUser => _currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser implements User {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
