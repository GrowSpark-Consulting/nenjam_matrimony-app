import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/location/presentation/widgets/location_picker_field.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_religion_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_basics_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// Country → State → City in the **signup** flow, backed by the location
/// master data.
///
/// Onboarding asks the country on the Religion step and the state and city
/// two steps later, so the cascade here spans screens in a way the Edit
/// Profile wizard's single-page version never has to. That is what most of
/// these pin: the parent's own screen cannot clear the children, so the rule
/// lives in the provider, and a member who backs up and changes country must
/// not carry a stale state and city forward into it.
///
/// Every test supplies [FakeLocationRepository]. A hardcoded fallback list
/// would make these pass while the real screen showed data that never came
/// from the server — which is the exact regression this migration removes.
void main() {
  GoRouter religionRouter() => GoRouter(
        initialLocation: RouteNames.onboardingReligion,
        routes: [
          GoRoute(
            path: RouteNames.onboardingReligion,
            builder: (_, _) => const OnboardingReligionPage(),
          ),
          GoRoute(
            path: RouteNames.onboardingContact,
            builder: (_, _) => const Scaffold(body: Text('contact-reached')),
          ),
        ],
      );

  GoRouter basicsRouter() => GoRouter(
        initialLocation: RouteNames.profileBasics,
        routes: [
          GoRoute(
            path: RouteNames.profileBasics,
            builder: (_, _) => const ProfileBasicsPage(),
          ),
          GoRoute(
            path: RouteNames.onboardingMarital,
            builder: (_, _) => const Scaffold(body: Text('marital-reached')),
          ),
        ],
      );

  ProviderContainer containerWith({
    RecordingRegistrationRepository? repository,
    FakeLocationRepository? locations,
    LocationDetails? location,
  }) {
    final container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider
            .overrideWithValue(repository ?? RecordingRegistrationRepository()),
        ...locationOverrides(locations ?? FakeLocationRepository()),
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
      ],
    );
    if (location != null) {
      container.read(registrationProvider.notifier).state =
          container.read(registrationProvider).copyWith(locationDetails: location);
    }
    return container;
  }

  /// A draft that already knows its country, which is the state step's
  /// precondition.
  const inIndia = LocationDetails(country: 'India', countryCode: 'IN');

  group('the options come from the backend', () {
    testWidgets('the country list is fetched, not hardcoded', (tester) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository();
      final container = containerWith(locations: locations);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      expect(locations.calls, contains('countries'));

      await tester.tap(
        find.ancestor(
          of: find.text('Living in *'),
          matching: find.byType(LocationPickerField),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly what the fake returned — no more, no less. A hardcoded
      // fallback would show countries the repository never sent.
      expect(find.text('Canada'), findsOneWidget);
      expect(find.text('Singapore'), findsNothing);
    });

    testWidgets('states are fetched for the chosen country only', (
      tester,
    ) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository();
      final container = containerWith(locations: locations, location: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      expect(locations.calls, contains('states:IN'));
      expect(locations.calls.where((c) => c.startsWith('states:')), hasLength(1));
    });

    testWidgets('cities are not fetched before a state is chosen', (
      tester,
    ) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository();
      final container = containerWith(locations: locations, location: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      // No state yet, so nothing to list cities for.
      expect(locations.calls.any((c) => c.startsWith('cities:')), isFalse);

      await pickLocation(tester, 'State *', 'Gujarat');
      expect(locations.calls, contains('cities:IN-GJ'));
    });
  });

  group('the cascade', () {
    testWidgets('choosing a state loads that state\'s cities', (tester) async {
      useTallSurface(tester);
      final container = containerWith(location: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      await pickLocation(tester, 'State *', 'Gujarat');
      await tester.tap(
        find.ancestor(
          of: find.text('City *'),
          matching: find.byType(LocationPickerField),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bhavnagar'), findsOneWidget);
      // Chennai belongs to Tamil Nadu, so it must not be offered here.
      expect(find.text('Chennai'), findsNothing);
    });

    testWidgets('changing the state clears the city', (tester) async {
      useTallSurface(tester);
      final container = containerWith(location: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      await pickLocation(tester, 'State *', 'Gujarat');
      await pickLocation(tester, 'City *', 'Bhavnagar');
      expect(find.text('Bhavnagar'), findsWidgets);

      await pickLocation(tester, 'State *', 'Tamil Nadu');

      // Unconditionally cleared: a city code is scoped to its state, so
      // carrying one across a state change would be a combination the server
      // rejects.
      expect(find.text('Bhavnagar'), findsNothing);
    });

    testWidgets('re-picking the same state keeps the city', (tester) async {
      useTallSurface(tester);
      final container = containerWith(location: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      await pickLocation(tester, 'State *', 'Gujarat');
      await pickLocation(tester, 'City *', 'Bhavnagar');
      await pickLocation(tester, 'State *', 'Gujarat');

      // Tapping your own state is not a change, and must not cost you an
      // answer you already gave.
      expect(find.text('Bhavnagar'), findsWidgets);
    });

    testWidgets('the city field is disabled until a state is chosen', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = containerWith(location: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      final city = tester.widget<LocationPickerField>(
        find.ancestor(
          of: find.text('City *'),
          matching: find.byType(LocationPickerField),
        ),
      );
      expect(city.enabled, isFalse);
    });

    testWidgets('the state field is disabled when no country is known', (
      tester,
    ) async {
      useTallSurface(tester);
      // A draft whose country is a label the master data does not offer.
      final container = containerWith(
        location: const LocationDetails(country: 'Atlantis'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      final state = tester.widget<LocationPickerField>(
        find.ancestor(
          of: find.text('State *'),
          matching: find.byType(LocationPickerField),
        ),
      );
      expect(state.enabled, isFalse);
    });
  });

  group('changing the country clears state and city', () {
    testWidgets('across the screen boundary, via the provider', (tester) async {
      useTallSurface(tester);
      final container = containerWith(
        location: const LocationDetails(
          country: 'India',
          countryCode: 'IN',
          state: 'Gujarat',
          stateCode: 'IN-GJ',
          city: 'Bhavnagar',
          cityCode: 'IN-GJ-BHAVNAGAR',
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      await pickDropdown(tester, 0, 'Hindu');
      await pickDropdown(tester, 1, 'Iyer');
      await pickLocation(tester, 'Living in *', 'Canada');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final location = container.read(registrationProvider).locationDetails;
      expect(location.countryCode, 'CA');
      // Gujarat and Bhavnagar are meaningless under Canada, and the server
      // would reject the combination outright.
      expect(location.state, isEmpty);
      expect(location.stateCode, isEmpty);
      expect(location.city, isEmpty);
      expect(location.cityCode, isEmpty);
    });

    testWidgets('keeping the same country keeps state and city', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = containerWith(
        location: const LocationDetails(
          country: 'India',
          countryCode: 'IN',
          state: 'Gujarat',
          stateCode: 'IN-GJ',
          city: 'Bhavnagar',
          cityCode: 'IN-GJ-BHAVNAGAR',
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      await pickDropdown(tester, 0, 'Hindu');
      await pickDropdown(tester, 1, 'Iyer');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Passing back through the step without touching the country must not
      // cost the member two answers given on a later screen.
      final location = container.read(registrationProvider).locationDetails;
      expect(location.state, 'Gujarat');
      expect(location.city, 'Bhavnagar');
      expect(location.cityCode, 'IN-GJ-BHAVNAGAR');
    });
  });

  group('codes are stored, not just labels', () {
    testWidgets('the state and city codes reach the draft and the backend', (
      tester,
    ) async {
      useTallSurface(tester);
      final repository = RecordingRegistrationRepository();
      final container =
          containerWith(repository: repository, location: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      await pickLocation(tester, 'State *', 'Gujarat');
      await pickLocation(tester, 'City *', 'Bhavnagar');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // The code is what the server validates; the label is what the member
      // reads back. Both travel.
      expect(repository.savedLocation?.stateCode, 'IN-GJ');
      expect(repository.savedLocation?.cityCode, 'IN-GJ-BHAVNAGAR');
      expect(repository.savedLocation?.state, 'Gujarat');
      expect(repository.savedLocation?.city, 'Bhavnagar');
    });

    testWidgets('a legacy label with no code gains one on save', (
      tester,
    ) async {
      useTallSurface(tester);
      final repository = RecordingRegistrationRepository();
      // Every new draft starts as country 'India' with no code, so this is
      // the common case, not an edge case. Without resolution the member
      // would have to re-pick a country their screen already shows, and the
      // State step would have nothing to list.
      final container = containerWith(
        repository: repository,
        location: const LocationDetails(country: 'India'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      await pickDropdown(tester, 0, 'Hindu');
      await pickDropdown(tester, 1, 'Iyer');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(repository.savedLocation?.countryCode, 'IN');
      expect(repository.savedLocation?.country, 'India');
    });

    testWidgets('an unrecognised label is left alone, never guessed at', (
      tester,
    ) async {
      useTallSurface(tester);
      final repository = RecordingRegistrationRepository();
      final container = containerWith(
        repository: repository,
        location: const LocationDetails(country: 'Atlantis'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      // Shown as the member's own answer rather than as an empty field...
      expect(find.text('Atlantis'), findsWidgets);

      await pickDropdown(tester, 0, 'Hindu');
      await pickDropdown(tester, 1, 'Iyer');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // ...and saved verbatim with no code. Inventing one is exactly what
      // the server refuses to do.
      expect(repository.savedLocation?.country, 'Atlantis');
      expect(repository.savedLocation?.countryCode, isEmpty);
    });
  });

  group('failure is visible and recoverable', () {
    testWidgets('a failed country load offers a retry, not an empty list', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = containerWith(
        locations: FakeLocationRepository(failCountries: true),
        // No stored country, so nothing masks the failure.
        location: const LocationDetails(country: ''),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      // A silently empty dropdown reads as "there is nothing here" when it
      // actually means "the request failed".
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a failed load still shows the answer already stored', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = containerWith(
        locations: FakeLocationRepository(failCountries: true),
        location: const LocationDetails(country: 'India'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      // The member's own answer outranks the error text — losing sight of it
      // because a request failed would look like the app forgot it.
      expect(find.text('India'), findsWidgets);
      expect(find.text('Could not load'), findsNothing);
      // The failure is still recoverable.
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a failed state load does not block the rest of the step', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = containerWith(
        locations: FakeLocationRepository(failStates: true),
        location: inIndia,
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsWidgets);
      // Sub-community is unrelated and must still be answerable.
      expect(find.byType(TextFormField), findsOneWidget);
    });
  });
}
