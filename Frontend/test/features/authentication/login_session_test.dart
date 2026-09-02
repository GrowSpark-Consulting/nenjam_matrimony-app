import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/data/models/auth_user.dart';
import 'package:nenjam_matrimony/features/authentication/data/repositories/auth_repository_impl.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/account_availability.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/local_auth_session.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/controllers/login_controller.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/splash/presentation/providers/splash_provider.dart';

/// Logging in must end in a session the rest of the app agrees with, and in
/// Discover — never in onboarding.
///
/// The two mobile routes are the ones with no Firebase session to point at
/// (nothing mints a phone credential while the OTP is the development
/// verifier), so they are the ones that can most easily end up "navigated
/// but not authenticated". These tests pin that they actually open a
/// session, that it survives a restart, and that logging out closes it.
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
    test('any non-empty code opens a session and reports success', () async {
      final container = _container();
      final controller = container.read(loginControllerProvider.notifier);

      for (final code in ['123456', '000000', '111111', '999999', '1234']) {
        await storageService.clearLocalSession();

        final result = await controller.loginWithMockOtp(
          phoneE164: '+919876543210',
          code: code,
        );

        expect(result.success, isTrue, reason: '"$code" must be accepted');
        expect(
          container.read(localAuthSessionProvider).isActive,
          isTrue,
          reason: 'the app must be authenticated, not merely navigated',
        );
        expect(
          container.read(localAuthSessionProvider).identifier,
          '+919876543210',
        );
      }
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
    test('a number the backend knows opens a session', () async {
      final container = _container(phoneExists: true);

      final result = await container
          .read(loginControllerProvider.notifier)
          .loginWithIdentifier(identifier: '9876543210', password: 'hunter22');

      expect(result.success, isTrue);
      expect(container.read(localAuthSessionProvider).isActive, isTrue);
      expect(
        container.read(localAuthSessionProvider).identifier,
        '+919876543210',
        reason: 'the number is normalised to E.164 before it is stored',
      );
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

ProviderContainer _container({
  bool phoneExists = true,
  bool lookupFails = false,
  bool signedOut = false,
}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
      accountAvailabilityProvider.overrideWithValue(
        _FakeAvailability(phoneExists: phoneExists, fails: lookupFails),
      ),
      if (signedOut)
        authStateChangesProvider.overrideWith((ref) => Stream.value(null)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
