import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/pages/login_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The login screen asks one question — which credential — and nothing else.
///
/// Sign-up used to share it as a second tab, which meant the screen had to
/// explain both flows at once and the Login button had to pass through a
/// chooser screen to get here. Sign-up now starts from the landing screen
/// and this one is login-only; these tests are what keep a signup CTA from
/// drifting back onto it.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });

  testWidgets('there is no Login / Sign Up tab switcher', (tester) async {
    await _pump(tester);

    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
  });

  testWidgets('no signup call to action appears anywhere on the screen',
      (tester) async {
    await _pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    for (final label in [
      l10n.authSignUp,
      l10n.authCreateAccount,
      l10n.authNewHere,
    ]) {
      expect(
        find.textContaining(label, findRichText: true),
        findsNothing,
        reason: '"$label" is a signup CTA and does not belong on login',
      );
    }
  });

  testWidgets('the login form itself is still there', (tester) async {
    await _pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // The mobile channel the form opens on, the channel switcher, and the
    // Google button — the screen is stripped of signup, not of login.
    expect(find.text(l10n.authChannelMobile), findsOneWidget);
    expect(find.text(l10n.authChannelEmail), findsOneWidget);
    expect(find.text(l10n.authLoginWithOtp), findsOneWidget);
    expect(find.text(l10n.authSignInWithGoogle), findsOneWidget);
  });

  testWidgets('the email channel keeps its password and Forgot Password',
      (tester) async {
    await _pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.text(l10n.authChannelEmail));
    await tester.pumpAndSettle();

    expect(find.text(l10n.authEmailAddress), findsOneWidget);
    expect(find.text(l10n.authPassword), findsOneWidget);
    expect(find.text(l10n.authForgotPassword), findsOneWidget);
    expect(find.text(l10n.authLogin), findsOneWidget);
  });

  testWidgets('identifier mode still opens one field for either credential',
      (tester) async {
    await _pump(tester, mode: LoginFormMode.identifier);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.authIdentifierLabel), findsOneWidget);
    expect(find.text(l10n.authPassword), findsOneWidget);
    // One field for both, so the channel switcher has nothing to switch.
    expect(find.text(l10n.authChannelMobile), findsNothing);
  });

  testWidgets('/login lands on the login form, with no screen in between',
      (tester) async {
    final router = await _pumpRouter(tester);

    router.push(RouteNames.login);
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(router.state.matchedLocation, RouteNames.loginForm);
  });

  // ─── The back arrow ─────────────────────────────────────────────────
  //
  // Welcome Back is reached two ways, and used to offer a way out of only
  // one of them: pushed from the landing screen it had an arrow, but as a
  // flow root (`go` from the splash or an OTP screen) it had none, so a
  // member who opened it by mistake was stuck on it.

  group('the back arrow', () {
    testWidgets('is shown when the screen was pushed, and pops', (
      tester,
    ) async {
      final router = await _pumpRouter(tester);
      router.push(RouteNames.loginForm);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.text('landing'), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets('is shown as a flow root too, and goes to the landing screen',
        (tester) async {
      final router = await _pumpRouter(tester);
      // `go`, not `push` — the stack is replaced, so there is nothing to pop.
      router.go(RouteNames.loginForm);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);

      expect(
        find.byIcon(Icons.arrow_back_rounded),
        findsOneWidget,
        reason: 'a screen with no way off it is the bug this fixes',
      );

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Falls back to the screen that precedes signing in rather than
      // popping an empty stack.
      expect(find.text('landing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Pumps the real [LoginPage] under a router — the page asks
/// `context.canPop()` for its back arrow, so it needs one even when the
/// test is only reading what is on screen.
Future<void> _pump(
  WidgetTester tester, {
  LoginFormMode mode = LoginFormMode.mobileOtp,
}) async {
  final router = GoRouter(
    initialLocation: RouteNames.loginForm,
    routes: [
      GoRoute(
        path: RouteNames.loginForm,
        builder: (_, __) => LoginPage(mode: mode),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mirrors the real router's two login routes: `/login` redirects to the
/// form, so every existing "send them to log in" call site arrives at the
/// form itself rather than at a chooser screen.
Future<GoRouter> _pumpRouter(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: RouteNames.registrationLanding,
    routes: [
      GoRoute(
        path: RouteNames.registrationLanding,
        builder: (_, __) => const Scaffold(body: Text('landing')),
      ),
      GoRoute(
        path: RouteNames.login,
        redirect: (_, __) => RouteNames.loginForm,
      ),
      GoRoute(
        path: RouteNames.loginForm,
        builder: (_, __) => const LoginPage(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}
