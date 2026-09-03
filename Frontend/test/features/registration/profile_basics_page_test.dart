import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_basics_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// The fourth and last onboarding screen: **State and City are required, and
/// answering them opens the Marital Status step** — not the retired 13-step wizard.
///
/// Sub-community is deliberately not asked here; it is not required to get a
/// member into Discover, and asking for it would put this screen out of step
/// with the gate in PostAuthDestination, which tests only these two.
void main() {
  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: RouteNames.profileBasics,
      routes: [
        GoRoute(
          path: RouteNames.profileBasics,
          builder: (context, state) => const ProfileBasicsPage(),
        ),
        GoRoute(
          path: RouteNames.onboardingMarital,
          builder: (context, state) =>
              const Scaffold(body: Text('marital-reached')),
        ),
        // Registered so a regression that routed back into the retired
        // wizard lands somewhere distinguishable instead of silently
        // failing to navigate.
        GoRoute(
          path: RouteNames.registrationWizard,
          builder: (context, state) =>
              const Scaffold(body: Text('wizard-reached')),
        ),
      ],
    );
  }

  ProviderContainer containerWith(RecordingRegistrationRepository repository) {
    return ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
        // Onboarding persists to the backend only with a session; without
        // this the steps would write locally and the repository would never
        // be called.
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
      ],
    );
  }

  testWidgets('Continue stays inert until both answers are given', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // Nothing answered: Continue must neither navigate nor write.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('marital-reached'), findsNothing);

    // One of two is still not enough — the gate is on every required
    // field, not on the member having touched the form.
    await pickDropdown(tester, 0, 'Tamil Nadu');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('marital-reached'), findsNothing);
    expect(container.read(registrationProvider).locationDetails.city, isEmpty);
  });

  testWidgets('answering both writes the draft, persists, and opens Marital Status', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await fillIdentity(tester);
    await pickDropdown(tester, 0, 'Tamil Nadu');
    await pickDropdown(tester, 1, 'Chennai');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final draft = container.read(registrationProvider);
    expect(draft.locationDetails.state, 'Tamil Nadu');
    expect(draft.locationDetails.city, 'Chennai');
    expect(draft.basicDetails.firstName, 'Arjun');
    expect(draft.basicDetails.lastName, 'Krishnan');
    expect(draft.basicDetails.gender, 'Male');
    expect(draft.basicDetails.dob, isNotNull);

    // Onboarding has no later step to sync for it, so the answers must
    // reach the backend here — otherwise the gate sends the member back.
    expect(repository.savedLocation?.state, 'Tamil Nadu');
    expect(repository.savedLocation?.city, 'Chennai');

    // The regression this screen exists to prevent: without the identity
    // fields reaching `basicDetails`, isMatchableFromDraft can never pass and
    // the backend writes no `user_profiles` row — the member finishes
    // onboarding and `GET /profiles/me` answers 404 forever.
    expect(repository.savedBasic?.firstName, 'Arjun');
    expect(repository.savedBasic?.lastName, 'Krishnan');
    expect(repository.savedBasic?.gender, 'Male');
    expect(repository.savedBasic?.dob, isNotNull);

    expect(find.text('marital-reached'), findsOneWidget);
    expect(find.text('wizard-reached'), findsNothing);
  });

  testWidgets('name, gender and date of birth are each required', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // State and city alone used to be the whole gate, which is exactly how a
    // member reached Discover with no profile row behind them.
    await pickDropdown(tester, 0, 'Tamil Nadu');
    await pickDropdown(tester, 1, 'Chennai');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('marital-reached'), findsNothing);

    // Name and gender still leave the date of birth outstanding.
    await tester.enterText(find.byType(TextFormField).at(0), 'Arjun');
    await tester.enterText(find.byType(TextFormField).at(1), 'Krishnan');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Male'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('marital-reached'), findsNothing);

    // Answering the last of them is what opens the step.
    await pickDob(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('marital-reached'), findsOneWidget);
  });

  testWidgets('a failed save keeps the member here rather than advancing', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository(failLocation: true);
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await fillIdentity(tester);
    await pickDropdown(tester, 0, 'Tamil Nadu');
    await pickDropdown(tester, 1, 'Chennai');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Advancing on a failed save would just bounce them back on the next
    // launch, because the gate reads the backend's copy.
    expect(find.text('marital-reached'), findsNothing);
  });

  testWidgets('the screen reopens on the answers already in the draft', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);
    // What PostAuthDestination rehydrates before sending a returning member
    // here — a resumed session must not blank what they already answered.
    container.read(registrationProvider.notifier).restore(
          ProfileDraft(
            basicDetails: BasicDetails(
              firstName: 'Meera',
              lastName: 'Rajan',
              gender: 'Female',
              dob: DateTime(1995, 3, 21),
            ),
            locationDetails: const LocationDetails(
              state: 'Karnataka',
              city: 'Bangalore',
            ),
          ),
          ProfileFlowMode.create,
        );

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // All restored, so Continue is live on arrival and carries the stored
    // values through unchanged.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final draft = container.read(registrationProvider);
    expect(draft.locationDetails.state, 'Karnataka');
    expect(draft.locationDetails.city, 'Bangalore');
    expect(draft.basicDetails.firstName, 'Meera');
    expect(draft.basicDetails.gender, 'Female');
    expect(draft.basicDetails.dob, DateTime(1995, 3, 21));
    expect(find.text('marital-reached'), findsOneWidget);
  });
}
