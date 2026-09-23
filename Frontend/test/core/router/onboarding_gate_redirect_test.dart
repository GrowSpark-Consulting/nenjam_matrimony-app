import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nenjam_matrimony/core/router/app_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/local_auth_session.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/utils/post_auth_destination.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Regression coverage for the router-level onboarding-gate bypass: the
/// `redirect:` callback in `app_router.dart` used to check only "is there a
/// session," so a signed-in-but-not-fully-onboarded member reaching a
/// protected route by any path other than the five screens that explicitly
/// call `PostAuthDestination.resolve()` (splash, login, phone/email verify)
/// — a deep link, restored nav state, or a programmatic `context.go` — landed
/// there with no onboarding check at all.
///
/// These tests drive the real `createRouter(ref)` end-to-end via
/// `router.go(...)`, so they exercise the actual `redirect:` logic rather
/// than a reimplementation of it.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });

  setUp(() async {
    await storageService.setLanguage('en');
    await storageService.clearLocalSession();
    await storageService.setOnboardingCompleted(false);
  });

  tearDown(() async {
    await storageService.clearLocalSession();
    await storageService.setOnboardingCompleted(false);
  });

  Future<GoRouter> pumpRouter(
    WidgetTester tester, {
    required FirebaseAuthService authService,
    required PostAuthDestination Function(Ref ref) postAuthDestination,
  }) async {
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(const _UnusedFirebaseAuth()),
          googleSignInProvider.overrideWithValue(const _UnusedGoogleSignIn()),
          firebaseAuthServiceProvider.overrideWithValue(authService),
          postAuthDestinationProvider.overrideWith(postAuthDestination),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = createRouter(ref);
            return MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  group('1. unauthenticated user — behavior unchanged', () {
    testWidgets('a signed-out visitor asking for a protected route is sent '
        'to the landing screen, never asked about onboarding', (
      tester,
    ) async {
      var resolveCalls = 0;
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: null),
        postAuthDestination: (ref) {
          resolveCalls++;
          return _FakeResolver(RouteNames.discover);
        },
      );

      router.go(RouteNames.discover);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.registrationLanding);
      expect(
        resolveCalls,
        0,
        reason: 'a signed-out visitor never reaches the onboarding check at '
            'all — it is unauthenticated, which is the only question this '
            'branch asks',
      );
    });

    testWidgets('public/onboarding routes stay reachable while signed out',
        (tester) async {
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: null),
        postAuthDestination: (ref) => _FakeResolver(RouteNames.discover),
      );

      router.go(RouteNames.onboardingAbout);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.onboardingAbout);
    });
  });

  group('2. authenticated + incomplete onboarding — redirected correctly', () {
    testWidgets('a deep link to a protected route is redirected to the '
        'onboarding step PostAuthDestination names', (tester) async {
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: _FakeUser()),
        postAuthDestination: (ref) =>
            _FakeResolver(RouteNames.onboardingAbout),
      );

      router.go(RouteNames.discover);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.onboardingAbout);
    });

    testWidgets('the same applies to a different protected destination '
        '(Settings, not just Discover)', (tester) async {
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: _FakeUser()),
        postAuthDestination: (ref) =>
            _FakeResolver(RouteNames.onboardingReligion),
      );

      router.go(RouteNames.settings);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.onboardingReligion);
    });

    testWidgets('an unverified-email gate redirects the same way', (
      tester,
    ) async {
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: _FakeUser()),
        postAuthDestination: (ref) => _FakeResolver(RouteNames.verifyEmail),
      );

      router.go(RouteNames.discover);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.verifyEmail);
    });
  });

  group('3. authenticated + complete onboarding — destination reachable', () {
    testWidgets('locally-known-complete onboarding reaches Discover without '
        'consulting the resolver at all', (tester) async {
      await storageService.setOnboardingCompleted(true);
      var resolveCalls = 0;
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: _FakeUser()),
        postAuthDestination: (ref) {
          resolveCalls++;
          return _FakeResolver(RouteNames.onboardingAbout);
        },
      );

      router.go(RouteNames.discover);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.discover);
      expect(
        resolveCalls,
        0,
        reason: 'the local onboardingCompleted flag is the fast path — a '
            'finished member must not pay for a resolver call on every '
            'ordinary navigation',
      );
    });

    testWidgets('a stale local flag (onboarding not marked complete on this '
        'device) still reaches Discover once the resolver confirms it', (
      tester,
    ) async {
      // onboardingCompleted is false here (see setUp) — the second-device /
      // reinstall case: the account is finished, this device just has not
      // learned that yet.
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: _FakeUser()),
        postAuthDestination: (ref) => _FakeResolver(RouteNames.discover),
      );

      router.go(RouteNames.discover);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.discover);
    });
  });

  group('4. direct/deep-link navigation cannot bypass the gate', () {
    testWidgets('going straight to a protected route with no prior '
        'PostAuthDestination call is still gated', (tester) async {
      // The exact bug: nothing in this test ever calls
      // postAuthDestinationProvider itself before router.go — the only
      // caller is the redirect guard.
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: _FakeUser()),
        postAuthDestination: (ref) =>
            _FakeResolver(RouteNames.createProfileFor),
      );

      router.go(RouteNames.profile);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.createProfileFor);
      expect(router.state.matchedLocation, isNot(RouteNames.profile));
    });

    testWidgets('a development-bridge session (LocalAuthSession, no '
        'Firebase user) is gated the same way', (tester) async {
      await storageService.setLocalSession(
        identifier: '+919876543210',
        method: LocalAuthMethod.mobileOtp.name,
      );
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: null),
        postAuthDestination: (ref) =>
            _FakeResolver(RouteNames.onboardingIncome),
      );

      router.go(RouteNames.matches);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.onboardingIncome);
    });
  });

  group('5. existing edit/profile flow is not broken', () {
    testWidgets('Edit Profile is reachable for a locally-complete member '
        'without ever being redirected by the onboarding gate', (
      tester,
    ) async {
      await storageService.setOnboardingCompleted(true);
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: _FakeUser()),
        postAuthDestination: (ref) => _FakeResolver(RouteNames.discover),
      );

      router.go(RouteNames.editProfile);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.editProfile);
    });

    testWidgets('Edit Profile stays reachable even with a stale local flag, '
        'as long as PostAuthDestination reports onboarding is done '
        '(second-device / reinstall case)', (tester) async {
      // onboardingCompleted is false (setUp) — this is the exact scenario
      // the fix has to get right: PostAuthDestination resolving to Discover
      // must not be read as "redirect every protected route to Discover."
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: _FakeUser()),
        postAuthDestination: (ref) => _FakeResolver(RouteNames.discover),
      );

      router.go(RouteNames.editProfile);
      await tester.pumpAndSettle();

      expect(
        router.state.matchedLocation,
        RouteNames.editProfile,
        reason: 'PostAuthDestination.resolve() returning Discover means '
            '"onboarding is done," not "go to Discover instead of wherever '
            'you were headed" — Edit Profile must remain reachable',
      );
    });

    testWidgets('Settings likewise stays reachable for a finished member '
        'with a stale local flag', (tester) async {
      final router = await pumpRouter(
        tester,
        authService: const _FakeAuthService(user: _FakeUser()),
        postAuthDestination: (ref) => _FakeResolver(RouteNames.discover),
      );

      router.go(RouteNames.settings);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.settings);
    });
  });
}

/// Never actually exercised — `firebaseAuthServiceProvider` is overridden
/// directly, so nothing constructs a real `FirebaseAuthService` from this —
/// but `authRepositoryProvider`'s `googleAuthServiceProvider` dependency
/// still watches `firebaseAuthProvider` directly and needs a value to not
/// reach the real SDK.
class _UnusedFirebaseAuth implements FirebaseAuth {
  const _UnusedFirebaseAuth();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedGoogleSignIn implements GoogleSignIn {
  const _UnusedGoogleSignIn();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserMetadata implements UserMetadata {
  const _FakeUserMetadata();

  @override
  DateTime? get creationTime => DateTime(2020, 1, 1);

  @override
  DateTime? get lastSignInTime => DateTime(2024, 6, 1);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser implements User {
  const _FakeUser();

  @override
  String get uid => 'fake-uid';

  @override
  String? get email => 'member@example.com';

  @override
  bool get emailVerified => true;

  @override
  String? get phoneNumber => '';

  @override
  UserMetadata get metadata => const _FakeUserMetadata();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthService implements FirebaseAuthService {
  const _FakeAuthService({required this.user});

  final User? user;

  @override
  User? get currentUser => user;

  @override
  Stream<User?> authStateChanges() => Stream.value(user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for [PostAuthDestination] so the router's own gating logic is
/// what these tests exercise, not the resolver's internal rules (those are
/// covered separately by `post_auth_destination_test.dart`).
class _FakeResolver implements PostAuthDestination {
  _FakeResolver(this._destination);

  final String _destination;

  @override
  Future<String> resolve() async => _destination;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
