import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nenjam_matrimony/core/services/storage_service.dart';

/// The parts of sign-out and OTP verification that decide whether a
/// session-less device can reach protected routes.
///
/// While signup ends in the static verifier, `onboardingCompleted` is what the
/// router accepts *in place of* a session (debug builds only — see
/// `_onboardingCompletedLocally`). That makes it a credential in everything
/// but name, and these tests pin the two properties that follow from it:
/// signing out has to revoke it, and a release build must not be able to mint
/// one by accepting any four digits.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sign-out', () {
    // `storageService` is a process-wide singleton holding a `late` field, so
    // init() can only ever run once — a per-test setUp throws
    // LateInitializationError on the second test. Each test sets the state it
    // needs instead of relying on a fresh store.
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await storageService.init();
    });

    test('clearing user data revokes the onboarding entry flag', () async {
      // Reproduces the logout hole: the flag used to survive sign-out, so a
      // signed-out device kept passing the router guard and a relaunch
      // resumed straight back into the app.
      await storageService.setOnboardingCompleted(true);
      expect(storageService.onboardingCompleted, isTrue);

      await storageService.clearUserData();

      expect(
        storageService.onboardingCompleted,
        isFalse,
        reason: 'sign-out must revoke the stand-in for a session too',
      );
    });

    test('clearing user data also drops the token and user id', () async {
      await storageService.saveTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
      );
      await storageService.setUserId('user-1');

      await storageService.clearUserData();

      expect(storageService.accessToken, isNull);
      expect(storageService.userId, isNull);
      expect(storageService.isLoggedIn, isFalse);
    });

    test('is idempotent — signing out twice is not an error', () async {
      await storageService.setOnboardingCompleted(true);

      await storageService.clearUserData();
      await storageService.clearUserData();

      expect(storageService.onboardingCompleted, isFalse);
    });
  });

  // Verifier selection is covered by `otp_verifier_selection_test.dart`, which
  // asserts it against BOTH branches of the compile-time switch rather than
  // only the debug default — an assertion pinned to "mock" would fail the
  // moment the suite runs down the release path.
}
