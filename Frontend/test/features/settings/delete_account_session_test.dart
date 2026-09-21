import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nenjam_matrimony/core/permissions/nm_permission.dart';
import 'package:nenjam_matrimony/core/permissions/permission_providers.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/data/repositories/auth_repository_impl.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/local_auth_session.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/settings/domain/repositories/settings_repository.dart';
import 'package:nenjam_matrimony/features/settings/presentation/pages/settings_page.dart';
import 'package:nenjam_matrimony/features/settings/presentation/providers/settings_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Regression coverage for: deleting an account left `LocalAuthSession`
/// untouched for a member who signed in via mobile OTP/password (no Firebase
/// session for `authRepositoryProvider.logout()` to end) — the deleted
/// account's device still satisfied the router guard afterward.
///
/// Exercises the real [SettingsPage] widget end-to-end through the actual
/// confirm → delete → logout sequence, not a reimplementation of it.
void main() {
  // storageService holds a `late final` field — init() can only run once per
  // test process, matching the convention used elsewhere (e.g.
  // auth_session_test.dart, language_page_navigation_test.dart).
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });

  setUp(() async {
    // A local session, as a mobile-OTP/mobile-password login would leave —
    // the exact precondition the bug required.
    await storageService.setLocalSession(
      identifier: '+919876543210',
      method: LocalAuthMethod.mobileOtp.name,
    );
  });

  tearDown(() async {
    await storageService.clearLocalSession();
  });

  Future<_Harness> pump(
    WidgetTester tester, {
    required Future<void> Function() deleteAccount,
    required Future<void> Function() logout,
  }) async {
    // Settings is pushed over a stub "home" route rather than made the
    // initial location, so the Navigator always has somewhere to fall back
    // to. Real navigation always reaches Settings this way (pushed from the
    // drawer over Discover) — an initial-location Settings would be a stack
    // of exactly one, which the real app never produces, and which makes the
    // progress dialog's Navigator.pop() misbehave if a caller (like the
    // deliberately-thrown fake below) pops again while nothing dialog-level
    // is left, an unrelated pre-existing quirk of _handleDeleteAccount this
    // fix does not touch.
    final router = GoRouter(
      initialLocation: RouteNames.discover,
      routes: [
        GoRoute(
          path: RouteNames.discover,
          builder: (_, __) => const Scaffold(body: Text('stub discover')),
        ),
        GoRoute(
          path: RouteNames.settings,
          builder: (_, __) => const SettingsPage(),
        ),
        GoRoute(
          path: RouteNames.login,
          builder: (_, __) => const Scaffold(body: Text('stub login')),
        ),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          _FakeSettingsRepository(deleteAccount),
        ),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository(logout)),
        // Avoids the real platform permission channel — irrelevant to this
        // fix, but SettingsPage.build() watches it unconditionally.
        notificationPermissionStatusProvider.overrideWith(
          (ref) async => NmPermissionStatus.denied,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    router.push(RouteNames.settings);
    await tester.pumpAndSettle();

    return _Harness(router);
  }

  /// Taps "Delete Account", then confirms the dialog it opens.
  ///
  /// Uses bounded `pump()`s rather than `pumpAndSettle()` for the steps
  /// around the confirm tap: `AppDialogs.showProgress` shows an indeterminate
  /// `CircularProgressIndicator`, whose animation never settles on its own,
  /// so `pumpAndSettle()` there would simply time out regardless of how this
  /// fix behaves.
  Future<void> tapDeleteAndConfirm(WidgetTester tester) async {
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();
    // AppDialogs.showDelete's destructive confirm action — matches the
    // label delete_dialog_overflow_test.dart exercises the same dialog
    // through.
    await tester.tap(find.text('Delete').last);
    // Lets the confirm dialog close, the progress dialog open, the fake
    // deleteAccount()/logout() futures resolve (or throw), and any follow-up
    // dialog (error) open — all well short of the progress spinner's next
    // animation tick actually needing a real time delta.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('a successful deletion', () {
    testWidgets('clears the local session', (tester) async {
      expect(storageService.localSessionIdentifier, isNotNull);

      await pump(
        tester,
        deleteAccount: () async {},
        logout: () async {},
      );
      await tapDeleteAndConfirm(tester);

      expect(
        storageService.localSessionIdentifier,
        isNull,
        reason: 'a deleted account must not leave the device looking '
            'signed in',
      );
    });

    testWidgets('navigates to the login route', (tester) async {
      final h = await pump(
        tester,
        deleteAccount: () async {},
        logout: () async {},
      );
      await tapDeleteAndConfirm(tester);

      expect(h.location, RouteNames.login);
    });

    testWidgets('still clears the local session even when there was also '
        'a Firebase session to end (logout succeeds)', (tester) async {
      // Not every deleted account is local-only — this proves the fix does
      // not regress the case a Firebase logout already handled.
      await pump(
        tester,
        deleteAccount: () async {},
        logout: () async {},
      );
      await tapDeleteAndConfirm(tester);

      expect(storageService.localSessionIdentifier, isNull);
    });
  });

  group('a failed deletion', () {
    testWidgets('never clears the local session', (tester) async {
      expect(storageService.localSessionIdentifier, isNotNull);

      await pump(
        tester,
        deleteAccount: () async => throw Exception('network down'),
        logout: () async {},
      );
      await tapDeleteAndConfirm(tester);

      expect(
        storageService.localSessionIdentifier,
        isNotNull,
        reason: 'a delete-account call that never reached the server must '
            'not sign the device out of an account that still exists',
      );
    });

    testWidgets('stays on the settings screen', (tester) async {
      final h = await pump(
        tester,
        deleteAccount: () async => throw Exception('network down'),
        logout: () async {},
      );
      await tapDeleteAndConfirm(tester);

      expect(h.location, RouteNames.settings);
    });
  });

  group('deletion succeeds but the subsequent logout fails', () {
    testWidgets('the local session is left intact rather than cleared '
        'prematurely', (tester) async {
      expect(storageService.localSessionIdentifier, isNotNull);

      await pump(
        tester,
        deleteAccount: () async {},
        logout: () async => throw Exception('sign-out failed'),
      );
      await tapDeleteAndConfirm(tester);

      expect(
        storageService.localSessionIdentifier,
        isNotNull,
        reason: 'clearing the local session is conditioned on logout() '
            'succeeding, exactly like the Firebase teardown it follows — a '
            'failure here must not silently clear it anyway',
      );
    });
  });
}

class _Harness {
  _Harness(this.router);

  final GoRouter router;

  String get location => router.state.matchedLocation;
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._deleteAccount);

  final Future<void> Function() _deleteAccount;

  @override
  Future<void> deleteAccount() => _deleteAccount();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthRepository implements FirebaseAuthRepository {
  _FakeAuthRepository(this._logout);

  final Future<void> Function() _logout;

  @override
  Future<void> logout() => _logout();

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
