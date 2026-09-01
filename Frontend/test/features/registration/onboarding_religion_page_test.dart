import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/onboarding_forms.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_religion_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// The second onboarding screen: **religion, community and "living in" are
/// all required**, and answering them hands off to the Email + Mobile step.
void main() {
  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: RouteNames.onboardingReligion,
      routes: [
        GoRoute(
          path: RouteNames.onboardingReligion,
          builder: (context, state) => const OnboardingReligionPage(),
        ),
        GoRoute(
          path: RouteNames.onboardingContact,
          builder: (context, state) =>
              const Scaffold(body: Text('contact-reached')),
        ),
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

  testWidgets('Continue stays inert until the unanswered fields are given', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // "Living in" opens on India: LocationDetails has always defaulted its
    // country, so that field arrives answered and only religion and
    // community are genuinely outstanding.
    expect(find.text('India'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('contact-reached'), findsNothing);

    // One of the two outstanding fields is not enough — every required
    // field gates the CTA, not just the member having touched the form.
    await pickDropdown(tester, 0, 'Hindu');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('contact-reached'), findsNothing);
    expect(
      container.read(registrationProvider).religionDetails.religion,
      isEmpty,
    );
  });

  testWidgets('answering all three persists and opens the contact step', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await pickDropdown(tester, 0, 'Hindu');
    await pickDropdown(tester, 1, 'Iyer');
    await pickDropdown(tester, 2, 'India');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final draft = container.read(registrationProvider);
    expect(draft.religionDetails.religion, 'Hindu');
    expect(draft.religionDetails.community, 'Iyer');
    // "Living in" is the country — the step before state and city, because
    // it decides whether those are the right questions at all.
    expect(draft.locationDetails.country, 'India');

    expect(repository.savedReligion?.religion, 'Hindu');
    expect(repository.savedLocation?.country, 'India');

    expect(find.text('contact-reached'), findsOneWidget);
    expect(find.text('wizard-reached'), findsNothing);
  });

  testWidgets('a failed save keeps the member here rather than advancing', (
    tester,
  ) async {
    useTallSurface(tester);
    final container =
        containerWith(RecordingRegistrationRepository(failReligion: true));
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await pickDropdown(tester, 0, 'Hindu');
    await pickDropdown(tester, 1, 'Iyer');
    await pickDropdown(tester, 2, 'India');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('contact-reached'), findsNothing);
  });

  testWidgets('the caste-no-bar box persists as an existing partner preference',
      (tester) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await pickDropdown(tester, 0, 'Hindu');
    await pickDropdown(tester, 1, 'Iyer');
    await pickDropdown(tester, 2, 'India');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Not a new concept: it is the "Any Caste" partner preference the
    // standalone Partner Preferences page already writes, through the same
    // repository call.
    expect(
      repository.savedPartnerPreference?.castePref,
      OnboardingReligionForm.casteNoBarPreference,
    );
    expect(find.text('contact-reached'), findsOneWidget);
  });

  testWidgets('an unticked box writes no partner preference at all', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await pickDropdown(tester, 0, 'Hindu');
    await pickDropdown(tester, 1, 'Iyer');
    await pickDropdown(tester, 2, 'India');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Leaving it unticked says nothing, so nothing is asserted on the
    // member's behalf — it must not be sent as "same caste".
    expect(repository.savedPartnerPreference, isNull);
    expect(find.text('contact-reached'), findsOneWidget);
  });

  testWidgets('the screen reopens on the answers already in the draft', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);
    container.read(registrationProvider.notifier).restore(
          const ProfileDraft(
            religionDetails:
                ReligionDetails(religion: 'Muslim', community: 'Urdu'),
            locationDetails: LocationDetails(country: 'Singapore'),
          ),
          ProfileFlowMode.create,
        );

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(repository.savedReligion?.religion, 'Muslim');
    expect(repository.savedReligion?.community, 'Urdu');
    expect(repository.savedLocation?.country, 'Singapore');
    expect(find.text('contact-reached'), findsOneWidget);
  });
}
