import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/data/models/auth_user.dart';
import 'package:nenjam_matrimony/features/authentication/data/repositories/auth_repository_impl.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/account_availability.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/dummy_otp_session.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/local_auth_session.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/controllers/login_controller.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/splash/presentation/providers/splash_provider.dart';

/// Logging in must end in a session the rest of the app agrees with, and in
/// Discover — never in onboarding.
///
/// The two mobile routes are the ones with no phone credential to point at
/// (nothing mints one while the OTP is the development verifier), so they are
/// the ones that can most easily end up "navigated but not authenticated".
///
/// Both now end the same way: the passed code (OTP) or the confirmed account
/// (password) is exchanged for a REAL Firebase session through the backend
/// ([DummyOtpSessionStarter]), and a failed exchange is a failed login —
/// letting someone in with no account behind them is the bug that exchange
/// exists to close.
///
/// Mobile + password used to record a [LocalAuthSession] instead. That marker
/// authenticated its requests by sending the phone number in an
/// `X-Dev-Auth-Phone` header, which the backend no longer honours: with
/// DUMMY_OTP_ENABLED it accepted any well-formed number with no credential,
/// and resolved to a different identity than the exchange returns.
///
/// These tests pin that each actually opens a session, that it survives a
/// restart, and that logging out closes it.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });

  setUp(() async {
    await storageService.clearLocalSession();
    await storageService.setOnboardingCompleted(false);
    await storageService.setLanguage('en');
  });

  group('mobile + OTP', () {
    test('any non-empty code is exchanged for a real Firebase session',
        () async {
      final starter = _RecordingStarter();
      final container = _container(starter: starter);
      final controller = container.read(loginControllerProvider.notifier);

      for (final code in ['123456', '000000', '111111', '999999', '1234']) {
        final result = await controller.loginWithMockOtp(
          phoneE164: '+919876543210',
          code: code,
        );

        expect(result.success, isTrue, reason: '"$code" must be accepted');
      }

      // The point of the exchange: the number the member typed is what the
      // backend is asked to provision, once per accepted code.
      expect(starter.phones, everyElement('+919876543210'));
      expect(starter.phones, hasLength(5));
    });

    test('a code the backend cannot turn into a session is a failed login',
        () async {
      // The dummy-OTP flags off, the number not whitelisted, Firebase Admin
      // unconfigured — whatever the reason, there is no account behind this
      // member, and reporting success would put them exactly where the old
      // LocalAuthSession did: navigated, unauthenticated, saving nothing.
      final container = _container(
        starter: _RecordingStarter(
          failure: DummyOtpSessionException('not enabled', statusCode: 403),
        ),
      );

      final result = await container
          .read(loginControllerProvider.notifier)
          .loginWithMockOtp(phoneE164: '+919876543210', code: '1234');

      expect(result.success, isFalse);
      expect(result.errorMessage, 'not enabled');
      expect(
        container.read(localAuthSessionProvider).isActive,
        isFalse,
        reason: 'a failed exchange must not fall back to a local marker',
      );
    });

    test('an empty code is refused and opens no session', () async {
      final container = _container();

      final result = await container
          .read(loginControllerProvider.notifier)
          .loginWithMockOtp(phoneE164: '+919876543210', code: '  ');

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(container.read(localAuthSessionProvider).isActive, isFalse);
    });
  });

  group('mobile + password', () {
    test('a number the backend knows opens a real Firebase session', () async {
      final starter = _RecordingStarter();
      final container = _container(phoneExists: true, starter: starter);

      final result = await container
          .read(loginControllerProvider.notifier)
          .loginWithIdentifier(identifier: '9876543210', password: 'hunter22');

      expect(result.success, isTrue);
      expect(
        starter.phones,
        ['+919876543210'],
        reason: 'the number is normalised to E.164 before it is exchanged, '
            'and the exchange is what authenticates the session',
      );
      expect(
        container.read(localAuthSessionProvider).isActive,
        isFalse,
        reason: 'no device-local marker: the header it backed is not an '
            'authentication mechanism any more',
      );
    });

    test('a failed exchange is a failed login', () async {
      // Succeeding here would put the member back in the state this replaced:
      // navigated into the app, unauthenticated against every API.
      final starter = _RecordingStarter(
        failure: DummyOtpSessionException('backend refused'),
      );
      final container = _container(phoneExists: true, starter: starter);

      final result = await container
          .read(loginControllerProvider.notifier)
          .loginWithIdentifier(identifier: '9876543210', password: 'hunter22');

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(container.read(localAuthSessionProvider).isActive, isFalse);
    });

    test('a number with no account is refused, never signed in', () async {
      final container = _container(phoneExists: false);

      final result = await container
          .read(loginControllerProvider.notifier)
          .loginWithIdentifier(identifier: '9876543210', password: 'hunter22');

      expect(result.success, isFalse);
      expect(container.read(localAuthSessionProvider).isActive, isFalse);
    });

    test('a lookup that fails is refused, not read as available', () async {
      final container = _container(lookupFails: true);

      final result = await container
          .read(loginControllerProvider.notifier)
          .loginWithIdentifier(identifier: '9876543210', password: 'hunter22');

      expect(result.success, isFalse);
      expect(container.read(localAuthSessionProvider).isActive, isFalse);
    });
  });

  group('the session the login leaves behind', () {
    test('reopening the app resolves to Discover, not onboarding', () async {
      // The cold start after a mobile login: Firebase has no user to
      // restore, so without the local session the splash would send the
      // member back to the landing screen and the login would look like it
      // had never happened.
      await storageService.setLocalSession(
        identifier: '+919876543210',
        method: 'mobileOtp',
      );

      final container = _container(signedOut: true);
      final route =
          await container.read(splashControllerProvider.notifier)
              .resolveInitialRoute();

      expect(route, RouteNames.discover);
      expect(route, isNot(RouteNames.registrationLanding));
      expect(route, isNot(RouteNames.onboardingContact));
    });

    test('with no session the splash still sends a visitor to the landing '
        'screen', () async {
      final container = _container(signedOut: true);

      expect(
        await container.read(splashControllerProvider.notifier)
            .resolveInitialRoute(),
        RouteNames.registrationLanding,
      );
    });

    test('logging out closes it', () async {
      await storageService.setLocalSession(
        identifier: '+919876543210',
        method: 'mobileOtp',
      );
      final container = _container();
      expect(container.read(localAuthSessionProvider).isActive, isTrue);

      await container.read(localAuthSessionProvider).clear();

      expect(container.read(localAuthSessionProvider).isActive, isFalse);
      expect(
        hasLocalAuthSession(),
        isFalse,
        reason: 'the router guard reads the same state and must agree',
      );
    });
  });
}

// ─── Fakes ───────────────────────────────────────────────────────────

class _FakeAvailability implements AccountAvailabilityChecker {
  _FakeAvailability({required this.phoneExists, required this.fails});

  final bool phoneExists;
  final bool fails;

  @override
  Future<AccountAvailability> check({
    required String email,
    required String phoneE164,
  }) async {
    if (fails) throw const AccountAvailabilityUnavailable();
    return AccountAvailability(emailExists: false, phoneExists: phoneExists);
  }
}

/// Stands in for the repository so nothing here needs a live Firebase. The
/// mobile routes never call it; it exists so building the provider graph
/// does not reach for `FirebaseAuth.instance`.
class _FakeAuthRepository implements FirebaseAuthRepository {
  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => Stream.value(null);

  @override
  AuthUser? get currentAuthUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the backend exchange. Records what it was asked to
/// provision so a test can assert the identity, and can be told to fail so the
/// "no account behind this member" branch is exercised without a server.
class _RecordingStarter implements DummyOtpSessionStarter {
  _RecordingStarter({this.failure});

  final DummyOtpSessionException? failure;
  final List<String> phones = <String>[];

  @override
  Future<String> start({required String phoneE164, String? email}) async {
    if (failure != null) throw failure!;
    phones.add(phoneE164);
    return 'firebase-uid-for-$phoneE164';
  }
}

ProviderContainer _container({
  bool phoneExists = true,
  bool lookupFails = false,
  bool signedOut = false,
  DummyOtpSessionStarter? starter,
}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
      accountAvailabilityProvider.overrideWithValue(
        _FakeAvailability(phoneExists: phoneExists, fails: lookupFails),
      ),
      dummyOtpSessionStarterProvider.overrideWithValue(
        starter ?? _RecordingStarter(),
      ),
      if (signedOut)
        authStateChangesProvider.overrideWith((ref) => Stream.value(null)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
