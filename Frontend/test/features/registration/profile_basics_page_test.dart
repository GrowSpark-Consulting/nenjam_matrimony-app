import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/onboarding_forms.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_basics_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// **State and City are required, and answering them opens the Marital Status
/// step** — not the retired 13-step wizard.
///
/// The screen asks three things and no more: State, City and Sub-community.
/// Gender moved to the Profile For step; name and date of birth have their
/// own step ([OnboardingNamePage]); caste and mother tongue are not collected
/// in onboarding at all.
///
/// Sub-community is asked but stays optional, because `sub_caste` is nullable
/// and the gate in PostAuthDestination does not test it — requiring it here
/// would gate a member on a field the router will happily wave them past.
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
          path: RouteNames.profileEdit,
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

    // One of four is still not enough — the gate is on every required
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

    await fillBasics(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final draft = container.read(registrationProvider);
    expect(draft.locationDetails.state, 'Tamil Nadu');
    expect(draft.locationDetails.city, 'Chennai');
    expect(draft.religionDetails.subCaste, 'Iyer');

    // Onboarding has no later step to sync for it, so the answers must
    // reach the backend here — otherwise the gate sends the member back.
    expect(repository.savedLocation?.state, 'Tamil Nadu');
    expect(repository.savedLocation?.city, 'Chennai');

    // Sub-community rides on the religion section, which is where
    // `user_profiles.sub_caste` is read from.
    expect(repository.savedReligion?.subCaste, 'Iyer');

    // The step neither asks for nor writes caste or mother tongue.
    expect(repository.savedReligion?.caste, isEmpty);
    expect(repository.savedSections, isNot(contains('languageDetails')));

    // Gender is not collected here any more, but `basicDetails` is still
    // sent: it carries the gender and name answered on the two steps before
    // this one, neither of which sends anything itself.
    expect(repository.savedSections, contains('basicDetails'));

    expect(find.text('marital-reached'), findsOneWidget);
    expect(find.text('wizard-reached'), findsNothing);
  });

  testWidgets('Gender is not on this screen', (tester) async {
    useTallSurface(tester);
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // No label, no chips, and no third selection control of any kind — the
    // question is asked once, on Profile For.
    expect(find.text('Gender'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Male'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Female'), findsNothing);
  });

  testWidgets('a gender answered earlier survives this step untouched', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);
    container.read(registrationProvider.notifier).applyProfileFor(
          const ProfileForForm(profileCreatedFor: 'Myself', gender: 'Female'),
        );

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await fillBasics(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // A screen that no longer asks a question must not be able to clear its
    // answer — and this is the step whose `basicDetails` PATCH carries it.
    expect(container.read(registrationProvider).basicDetails.gender, 'Female');
    expect(repository.savedBasic?.gender, 'Female');
    expect(repository.savedBasic?.toJson()['gender'], 'FEMALE');
  });

  testWidgets('sub-community is optional and is not sent when left blank', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await fillBasics(tester, subCommunity: '');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Blank is a complete answer — the step advances.
    expect(find.text('marital-reached'), findsOneWidget);
    expect(container.read(registrationProvider).religionDetails.subCaste,
        isEmpty);
    // And no religion PATCH goes out for a field nobody changed, so this
    // step cannot overwrite a sub-caste Edit Profile had already stored.
    expect(repository.savedSections, isNot(contains('religionDetails')));
  });

  testWidgets('the screen asks for State, City and Sub-community and nothing '
      'else', (tester) async {
    useTallSurface(tester);
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // Two dropdowns (State, City) and one text field (Sub-community). Caste
    // and Mother tongue are not on this screen, and neither is Gender.
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('Caste'), findsNothing);
    expect(find.text('Caste *'), findsNothing);
    expect(find.text('Mother Tongue'), findsNothing);
    expect(find.text('Mother Tongue *'), findsNothing);
    expect(find.text('Gender'), findsNothing);

    // State alone is not enough; City is what completes the step.
    await pickDropdown(tester, 0, 'Tamil Nadu');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('marital-reached'), findsNothing);

    await pickDropdown(tester, 1, 'Chennai');
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

    await fillBasics(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Advancing on a failed save would just bounce them back on the next
    // launch, because the gate reads the backend's copy.
    expect(find.text('marital-reached'), findsNothing);

    // And the answers the member gave are still on the screen and in the
    // draft — a failed API call must not cost them the form.
    // The dropdowns still show what was picked — a failed API call must not
    // cost the member the form.
    expect(find.text('Tamil Nadu'), findsWidgets);
    expect(find.text('Chennai'), findsWidgets);
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
          const ProfileDraft(
            religionDetails: ReligionDetails(subCaste: 'Iyengar'),
            locationDetails: LocationDetails(
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
    expect(draft.religionDetails.subCaste, 'Iyengar');
    expect(find.text('marital-reached'), findsOneWidget);
  });
}
