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

  testWidgets('answering every field persists and opens the contact step', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await pickDropdown(tester, 0, 'Hindu');
    // Caste is free text, so it sits between the Religion and Community
    // dropdowns without being one — hence Living in is now index 3.
    // Deliberately not 'Iyer': a caste equal to the community would make
    // pickDropdown's `find.text(...).last` ambiguous against this field.
    await tester.enterText(find.byType(TextFormField).first, 'Iyengar');
    await tester.pumpAndSettle();
    await pickDropdown(tester, 1, 'Iyer');
    await pickDropdown(tester, 2, 'Tamil');
    await pickDropdown(tester, 3, 'India');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final draft = container.read(registrationProvider);
    expect(draft.religionDetails.religion, 'Hindu');
    expect(draft.religionDetails.caste, 'Iyengar');
    expect(draft.religionDetails.community, 'Iyer');
    expect(draft.languageDetails.motherTongue, 'Tamil');
    // "Living in" is the country — the step before state and city, because
    // it decides whether those are the right questions at all.
    expect(draft.locationDetails.country, 'India');

    expect(repository.savedReligion?.religion, 'Hindu');
    expect(repository.savedLocation?.country, 'India');

    // The regression this step exists to prevent: `caste` and `mother_tongue`
    // are NOT NULL on `user_profiles`, so if they never reach the backend
    // isMatchableFromDraft cannot pass, no profile row is written, and the
    // member finishes onboarding to a permanent 404 from GET /profiles/me.
    expect(repository.savedReligion?.caste, 'Iyengar');
    expect(repository.savedLanguage?.motherTongue, 'Tamil');

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
    // Caste is free text, so it sits between the Religion and Community
    // dropdowns without being one — hence Living in is now index 3.
    // Deliberately not 'Iyer': a caste equal to the community would make
    // pickDropdown's `find.text(...).last` ambiguous against this field.
    await tester.enterText(find.byType(TextFormField).first, 'Iyengar');
    await tester.pumpAndSettle();
    await pickDropdown(tester, 1, 'Iyer');
    await pickDropdown(tester, 2, 'Tamil');
    await pickDropdown(tester, 3, 'India');
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
    // Caste is free text, so it sits between the Religion and Community
    // dropdowns without being one — hence Living in is now index 3.
    // Deliberately not 'Iyer': a caste equal to the community would make
    // pickDropdown's `find.text(...).last` ambiguous against this field.
    await tester.enterText(find.byType(TextFormField).first, 'Iyengar');
    await tester.pumpAndSettle();
    await pickDropdown(tester, 1, 'Iyer');
    await pickDropdown(tester, 2, 'Tamil');
    await pickDropdown(tester, 3, 'India');
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
    // Caste is free text, so it sits between the Religion and Community
    // dropdowns without being one — hence Living in is now index 3.
    // Deliberately not 'Iyer': a caste equal to the community would make
    // pickDropdown's `find.text(...).last` ambiguous against this field.
    await tester.enterText(find.byType(TextFormField).first, 'Iyengar');
    await tester.pumpAndSettle();
    await pickDropdown(tester, 1, 'Iyer');
    await pickDropdown(tester, 2, 'Tamil');
    await pickDropdown(tester, 3, 'India');
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
            religionDetails: ReligionDetails(
              religion: 'Muslim',
              caste: 'Sunni',
              community: 'Urdu',
            ),
            languageDetails: LanguageDetails(motherTongue: 'Urdu'),
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
    // Restored verbatim, so a resumed session carries the two NOT NULL
    // answers through rather than blanking them and stranding the member
    // without a profile row.
    expect(repository.savedReligion?.caste, 'Sunni');
    expect(repository.savedLanguage?.motherTongue, 'Urdu');
    expect(find.text('contact-reached'), findsOneWidget);
  });
}
