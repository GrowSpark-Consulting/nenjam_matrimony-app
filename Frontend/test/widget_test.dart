import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nenjam_matrimony/core/network/api_providers.dart';
import 'package:nenjam_matrimony/core/network/backend_connectivity_checker.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smoke test: the root widget builds, mounts a router, and renders a first
/// screen without throwing.
///
/// [NenjamMatrimonyApp] reaches for three platform singletons the moment it is
/// constructed — `FirebaseAuth.instance` (via `createRouter`'s auth stream),
/// `GoogleSignIn.instance`, and a live backend health probe from the splash.
/// None of those exist in a unit test: `main()` is what calls
/// `Firebase.initializeApp`, and this test deliberately bypasses `main()` to
/// pump the widget directly. That is why the test used to fail with
/// `[core/no-app] No Firebase App '[DEFAULT]' has been created` before the
/// first frame ever rendered.
///
/// Each one is replaced below with a fake, so the test exercises the widget
/// tree rather than the device's Firebase and network stack. `noSuchMethod`
/// forwarding lets each fake implement only the members actually reached,
/// without standing up the full SDK surface.

/// Signed out, and settled: a null user means [currentAuthUserProvider] is
/// null, which is what keeps `realtimeSyncProvider`,
/// `chatRealtimeSyncProvider` and `pushNotificationSyncProvider` in their
/// disconnected branches — no socket, no FCM registration.
class _FakeFirebaseAuth implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => Stream<User?>.value(null);

  @override
  Stream<User?> idTokenChanges() => Stream<User?>.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleSignIn implements GoogleSignIn {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Reports a healthy backend without a request, so the splash proceeds to
/// route instead of parking on its retry state. With empty SharedPreferences
/// no language has been chosen, so `resolveInitialRoute` returns the language
/// screen immediately — before it touches Firebase or the network at all.
class _FakeHealthChecker implements BackendConnectivityChecker {
  @override
  Future<BackendConnectivityResult> check() async => const BackendHealthy();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Setup mock shared preferences for local storage
    SharedPreferences.setMockInitialValues({});
    await storageService.init();

    // Set screen size for test environment
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(_FakeFirebaseAuth()),
          googleSignInProvider.overrideWithValue(_FakeGoogleSignIn()),
          serverHealthCheckerProvider.overrideWithValue(_FakeHealthChecker()),
        ],
        child: const NenjamMatrimonyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify app builds without crashing
    expect(find.byType(NenjamMatrimonyApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
