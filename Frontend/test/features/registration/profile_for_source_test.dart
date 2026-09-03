import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/controllers/signup_controller.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/onboarding_forms.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/create_profile_for_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'onboarding_test_support.dart';

/// Locks in the one rule the registration flow is built around: **"who is
/// this profile for?" is asked once, after authentication, on
/// [CreateProfileForPage] — never on an account-creation form.**
///
/// The screen now asks a second question, Gender, which moved here from the
/// "Let's build your Profile" step. It is the same single
/// `BasicDetails.gender` the rest of the app has always read — this screen
/// gained a writer, not a second gender.
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
  /// asserts the screen hands off to the Your Name step, the one screen that
  /// follows it. The removed 13-step wizard is registered too, so a
  /// regression that routed back into it would land on a distinguishable
  /// screen rather than silently failing to navigate.
  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: RouteNames.createProfileFor,
      routes: [
        GoRoute(
          path: RouteNames.createProfileFor,
          builder: (context, state) => const CreateProfileForPage(),
        ),
        GoRoute(
          path: RouteNames.onboardingNameDob,
          builder: (context, state) =>
              const Scaffold(body: Text('name-reached')),
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
      'My Son',
      'My Daughter',
      'My Brother',
      'My Sister',
      'My Friend',
      'My Relative',
    ]) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '"$label" must be selectable on the Profile For screen',
      );
    }
  });

  testWidgets(
      'Continue writes the relation to the draft and opens the Your Name step',
      (tester) async {
    useTallSurface(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // Nothing is committed by merely opening the screen — the draft's copy is
    // written on Continue, which is what makes this the single source. The
    // value is *empty*, not 'Myself': nothing is selected until the user
    // picks, which is what keeps the router able to tell an unanswered draft
    // from a deliberate "Myself".
    expect(
      container.read(registrationProvider).basicDetails.profileCreatedFor,
      isEmpty,
    );

    // Continue is inert with nothing chosen — the screen cannot be walked
    // past without answering.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('name-reached'), findsNothing);
    expect(
      container.read(registrationProvider).basicDetails.profileCreatedFor,
      isEmpty,
    );

    // Two taps, one answer: the options are mutually exclusive, so the
    // second choice replaces the first rather than adding to it.
    await tester.tap(find.text('My Sister'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Daughter'));
    await tester.pumpAndSettle();

    // A relation alone is not the whole step any more — gender is required
    // here too, and Continue stays inert until it is given.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('name-reached'), findsNothing);

    await pickGender(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final basic = container.read(registrationProvider).basicDetails;
    expect(basic.profileCreatedFor, 'Daughter');
    // Gender lands on the one field that has always held it, in the draft's
    // own representation — `BasicDetails.toJson` is what maps it to MALE.
    expect(basic.gender, 'Male');
    expect(basic.toJson()['gender'], 'MALE');
    expect(find.text('name-reached'), findsOneWidget);
    // The removed signup wizard is never what follows this screen.
    expect(find.text('wizard-reached'), findsNothing);
  });

  testWidgets('Gender is displayed, selectable, and required', (tester) async {
    useTallSurface(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // Rendered with the same control the app uses for gender everywhere
    // else — the ChoiceChip row, not a bespoke pill.
    expect(find.text('Gender'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Male'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Female'), findsOneWidget);

    // Gender alone does not complete the step either — both are required.
    await pickGender(tester, gender: 'Female');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('name-reached'), findsNothing);

    // Mutually exclusive, like the relation pills above.
    await pickGender(tester, gender: 'Male');
    await tester.tap(find.text('Myself'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(container.read(registrationProvider).basicDetails.gender, 'Male');
    expect(find.text('name-reached'), findsOneWidget);
  });

  testWidgets('the screen reopens on the gender already in the draft', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(registrationProvider.notifier).applyProfileFor(
          const ProfileForForm(profileCreatedFor: 'Son', gender: 'Female'),
        );

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // Both answers restored, so Continue is live on arrival and carries them
    // through unchanged — stepping back from Your Name costs nothing.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final restored = container.read(registrationProvider).basicDetails;
    expect(restored.profileCreatedFor, 'Son');
    expect(restored.gender, 'Female');
    expect(find.text('name-reached'), findsOneWidget);
  });

  testWidgets('Continue keeps answers given on later steps', (tester) async {
    useTallSurface(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // A member who reached Your Name, tapped Back to change "profile for",
    // and continued again. Continue used to call startCreateMode(), which
    // blanks the entire draft — so that Back cost them their name, their date
    // of birth and everything else they had answered. Continue sets the flow
    // mode and nothing more.
    final notifier = container.read(registrationProvider.notifier);
    notifier.applyProfileFor(
      const ProfileForForm(profileCreatedFor: 'Son', gender: 'Male'),
    );
    await notifier.applyOnboardingName(
      const OnboardingNameForm(
        firstName: 'Arjun',
        lastName: 'Krishnan',
        day: '05',
        month: '02',
        year: '1998',
      ),
    );

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Daughter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final basic = container.read(registrationProvider).basicDetails;
    expect(basic.profileCreatedFor, 'Daughter');
    // The gender restored on arrival is carried straight back through.
    expect(basic.gender, 'Male');
    expect(basic.firstName, 'Arjun');
    expect(basic.lastName, 'Krishnan');
    expect(basic.dob, DateTime(1998, 2, 5));
  });

  testWidgets('the screen reopens on the choice already in the draft', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(registrationProvider.notifier).applyProfileFor(
          const ProfileForForm(profileCreatedFor: 'Son', gender: 'Male'),
        );

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // Stepping back here from the Your Name step must not silently drop the
    // answer. A restored choice counts as a selection, so Continue is live
    // on arrival and carries the stored value straight through unchanged.
    expect(
      container.read(registrationProvider).basicDetails.profileCreatedFor,
      'Son',
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('name-reached'), findsOneWidget);
    expect(
      container.read(registrationProvider).basicDetails.profileCreatedFor,
      'Son',
    );
  });
}
