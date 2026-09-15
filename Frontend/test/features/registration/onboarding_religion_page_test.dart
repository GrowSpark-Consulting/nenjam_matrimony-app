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

import 'package:nenjam_matrimony/features/location/presentation/widgets/location_picker_field.dart';

import 'onboarding_test_support.dart';

/// The third onboarding screen: **religion, community and "living in" are
/// all required**, and answering them hands off to the Email + Mobile step.
///
/// Caste and mother tongue are deliberately NOT on this screen any more. They
/// moved to the "Let's build your Profile" step, which is where they are now
/// asked, validated and sent — see profile_basics_page_test.dart. Nothing was
/// deleted: both remain NOT NULL on `user_profiles`, and the tests below pin
/// that this screen neither displays nor clears them.
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
          path: RouteNames.profileEdit,
          builder: (context, state) =>
              const Scaffold(body: Text('wizard-reached')),
        ),
      ],
    );
  }

  ProviderContainer containerWith(
    RecordingRegistrationRepository repository, {
    FakeLocationRepository? locations,
  }) {
    return ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
        // "Living in" is backed by the location master data now, so every
        // test supplies it. Without this the page would try to reach the
        // network — and must never silently fall back to a hardcoded list.
        ...locationOverrides(locations ?? FakeLocationRepository()),
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
    await pickLocation(tester, 'Religion *', 'Hindu');
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

    await fillReligionStep(tester, religion: 'Hindu', community: 'Iyer');
    await pickLocation(tester, 'Living in *', 'India');
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

    // This step no longer speaks for the language section at all — the
    // "Let's build your Profile" step owns mother tongue now, and a PATCH
    // from here would be this screen writing a field it never asked for.
    expect(repository.savedSections, isNot(contains('languageDetails')));

    expect(find.text('contact-reached'), findsOneWidget);
    expect(find.text('wizard-reached'), findsNothing);
  });

  testWidgets('Caste and Mother tongue are not on this screen', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // Neither label appears anywhere on the page...
    expect(find.text('Caste'), findsNothing);
    expect(find.text('Caste *'), findsNothing);
    expect(find.text('Mother Tongue'), findsNothing);
    expect(find.text('Mother Tongue *'), findsNothing);

    // ...and there is no free-text input left at all: caste was the only
    // text field. All three fields on this screen — religion, community and
    // "Living in" — are now backend-backed reference-data pickers, so none of
    // them is a DropdownButtonFormField any more.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(LocationPickerField), findsNWidgets(3));

    // The partner-community opt-out is a different field — PartnerPreference
    // .castePref, not the member's own caste — and deliberately stays.
    expect(find.byType(Checkbox), findsOneWidget);
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

    await fillReligionStep(tester, religion: 'Hindu', community: 'Iyer');
    await pickLocation(tester, 'Living in *', 'India');
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

    await fillReligionStep(tester, religion: 'Hindu', community: 'Iyer');
    await pickLocation(tester, 'Living in *', 'India');
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

    await fillReligionStep(tester, religion: 'Hindu', community: 'Iyer');
    await pickLocation(tester, 'Living in *', 'India');
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
    // Neither is asked here any more, and neither may be lost by saving
    // here: the notifier copies the stored values through untouched, so a
    // member who answered them before the move keeps them.
    expect(repository.savedReligion?.caste, 'Sunni');
    expect(container.read(registrationProvider).languageDetails.motherTongue,
        'Urdu');
    expect(find.text('contact-reached'), findsOneWidget);
  });
}
