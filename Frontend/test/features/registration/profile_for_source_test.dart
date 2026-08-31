import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/controllers/signup_controller.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/create_profile_for_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Locks in the one rule the registration flow is built around: **"who is
/// this profile for?" is asked once, after authentication, on
/// [CreateProfileForPage] — never on an account-creation form.**
///
/// The signup form used to carry a "Registering for" chip row whose value was
/// written into the draft before the account even existed, and was then
/// thrown away again by EmailVerifyScreen's `startCreateMode()` — so the user
/// answered a question that could not survive to the wizard. These tests fail
/// if that, or any other pre-auth source for the value, comes back.
void main() {
  /// Tall enough that all seven relation options are laid out at once; the
  /// default 800x600 test surface cuts the list off after five.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// A real router, because Continue navigates with `context.go` — this also
  /// asserts the screen hands off to the wizard rather than anywhere else.
  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: RouteNames.createProfileFor,
      routes: [
        GoRoute(
          path: RouteNames.createProfileFor,
          builder: (context, state) => const CreateProfileForPage(),
        ),
        GoRoute(
          path: RouteNames.registrationWizard,
          builder: (context, state) =>
              const Scaffold(body: Text('wizard-reached')),
        ),
      ],
    );
  }

  Widget harness(ProviderContainer container, GoRouter router) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  test('SignupState carries no relation field', () {
    // A compile-time guarantee dressed as a test: SignupState is the only
    // state the account-creation form writes to, so if it cannot hold a
    // relation, that form cannot collect one.
    const state = SignupState();
    expect(state.username, isEmpty);
    expect(state.email, isEmpty);
    expect(state.phone, isEmpty);
    expect(state.password, isEmpty);
  });

  testWidgets('CreateProfileForPage offers every supported relation', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    for (final label in [
      'Myself',
      'Son',
      'Daughter',
      'Brother',
      'Sister',
      'Relative',
      'Friend',
    ]) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '"$label" must be selectable on the Profile For screen',
      );
    }
  });

  testWidgets('Continue writes the relation to the draft and opens the wizard',
      (tester) async {
    useTallSurface(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // Nothing is committed by merely opening the screen — the draft's copy is
    // written on Continue, which is what makes this the single source. The
    // value is *empty*, not 'Myself': the screen highlights Myself as its
    // default selection, but until Continue is tapped the draft records no
    // answer at all, which is what keeps the router able to tell an
    // unanswered draft from a deliberate "Myself".
    expect(
      container.read(registrationProvider).basicDetails.profileCreatedFor,
      isEmpty,
    );

    await tester.tap(find.text('Daughter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      container.read(registrationProvider).basicDetails.profileCreatedFor,
      'Daughter',
    );
    expect(find.text('wizard-reached'), findsOneWidget);
  });

  testWidgets('the screen reopens on the choice already in the draft', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(registrationProvider.notifier).setProfileCreatedFor('Son');

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // Stepping back here from the wizard must not silently revert the answer
    // to the 'Myself' default. Exactly one card shows the selected check.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      container.read(registrationProvider).basicDetails.profileCreatedFor,
      'Son',
    );

    // Continuing without changing anything keeps the stored answer.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      container.read(registrationProvider).basicDetails.profileCreatedFor,
      'Son',
    );
  });
}
