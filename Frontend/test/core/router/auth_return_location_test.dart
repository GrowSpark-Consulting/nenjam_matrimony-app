import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nenjam_matrimony/core/router/app_router.dart';
import 'package:nenjam_matrimony/core/router/auth_return_location.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/utils/post_auth_destination.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// A signed-out visitor following a link (a shared profile, a bookmarked
/// chat, a reload after the session lapsed) is bounced to the landing screen;
/// logging in should then finish the trip rather than always ending on
/// Discover — without ever skipping an onboarding step, and without a
/// sign-out handing the previous member's page to whoever logs in next.
void main() {
  setUp(AuthReturnLocation.clear);

  group('AuthReturnLocation', () {
    test('returns the remembered link in place of Discover, once', () {
      AuthReturnLocation.remember('/profile-detail/abc');

      expect(
        AuthReturnLocation.afterLogin(RouteNames.discover),
        '/profile-detail/abc',
      );
      expect(
        AuthReturnLocation.afterLogin(RouteNames.discover),
        RouteNames.discover,
        reason: 'consumed by the first login',
      );
    });

    test('an onboarding step still owed wins over the remembered link', () {
      AuthReturnLocation.remember(RouteNames.settings);

      expect(
        AuthReturnLocation.afterLogin(RouteNames.onboardingAbout),
        RouteNames.onboardingAbout,
      );
      expect(AuthReturnLocation.pending, isNull);
    });

    test('ignores public routes and anything that is not an in-app path', () {
      AuthReturnLocation.remember(RouteNames.loginForm);
      expect(AuthReturnLocation.pending, isNull);

      AuthReturnLocation.remember('//evil.example/x');
      expect(AuthReturnLocation.pending, isNull);

      AuthReturnLocation.remember('https://evil.example/x');
      expect(AuthReturnLocation.pending, isNull);
    });

    test('keeps the query string', () {
      AuthReturnLocation.remember(
        '/profile-viewers?openedFromNotification=true',
      );
      expect(
        AuthReturnLocation.afterLogin(RouteNames.discover),
        '/profile-viewers?openedFromNotification=true',
      );
    });
  });

  group('router guard', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await storageService.init();
    });

    setUp(() async {
      await storageService.setLanguage('en');
      await storageService.clearLocalSession();
      await storageService.setOnboardingCompleted(false);
    });

    Future<GoRouter> pumpRouter(
      WidgetTester tester,
      FirebaseAuthService authService,
    ) async {
      late GoRouter router;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(const _UnusedFirebaseAuth()),
            googleSignInProvider.overrideWithValue(const _UnusedGoogleSignIn()),
            firebaseAuthServiceProvider.overrideWithValue(authService),
            postAuthDestinationProvider.overrideWith(
              (ref) => _FakeResolver(RouteNames.discover),
            ),
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

    testWidgets('a signed-out visitor to a protected link is still sent to '
        'the landing screen, and the link is remembered', (tester) async {
      final router = await pumpRouter(tester, _FakeAuthService.signedOut());

      router.go(RouteNames.settings);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.registrationLanding);
      expect(AuthReturnLocation.pending, RouteNames.settings);
    });

    testWidgets('signing out does not remember the page the member was on', (
      tester,
    ) async {
      await storageService.setOnboardingCompleted(true);
      final auth = _FakeAuthService.signedIn();
      final router = await pumpRouter(tester, auth);

      router.go(RouteNames.settings);
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, RouteNames.settings);

      await storageService.setOnboardingCompleted(false);
      auth.emitSignOut();
      await tester.pumpAndSettle();
      // In the app the router's refreshListenable re-runs the redirect on
      // this emission; it listens to the raw FirebaseAuth stream, which this
      // harness stubs out, so trigger that same re-run directly.
      router.refresh();
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.registrationLanding);
      expect(
        AuthReturnLocation.pending,
        isNull,
        reason:
            'the next person to log in on this browser must not be '
            'dropped on the previous member\'s page',
      );
    });
  });
}

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

/// Emits the current user to every listener, then any later sign-out.
class _FakeAuthService implements FirebaseAuthService {
  _FakeAuthService._(this._user);

  factory _FakeAuthService.signedIn() => _FakeAuthService._(const _FakeUser());
  factory _FakeAuthService.signedOut() => _FakeAuthService._(null);

  User? _user;
  final _changes = StreamController<User?>.broadcast();

  void emitSignOut() {
    _user = null;
    _changes.add(null);
  }

  @override
  User? get currentUser => _user;

  @override
  Stream<User?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResolver implements PostAuthDestination {
  _FakeResolver(this._destination);

  final String _destination;

  @override
  Future<String> resolve() async => _destination;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
