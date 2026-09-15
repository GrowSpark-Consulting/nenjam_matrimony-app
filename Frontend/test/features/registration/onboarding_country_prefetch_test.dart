import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/location/presentation/providers/location_providers.dart';
import 'package:nenjam_matrimony/features/location/presentation/widgets/location_picker_field.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/create_profile_for_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_religion_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_basics_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// Prefetching the country list when onboarding starts.
///
/// The measurement behind this: the country request costs ~290ms of network
/// round trip and effectively zero server time, so it cannot be made faster —
/// only spent earlier. Onboarding's first screen asks "who is this profile
/// for", and the country is not asked until two screens later, which is
/// enough time for the request to finish unnoticed.
///
/// What these pin is that the warm-up is *free*: it must never turn one
/// request into two, and it must never change what the country field does
/// when the list is missing, slow or broken.
void main() {
  GoRouter onboardingRouter() => GoRouter(
        initialLocation: RouteNames.createProfileFor,
        routes: [
          GoRoute(
            path: RouteNames.createProfileFor,
            builder: (_, _) => const CreateProfileForPage(),
          ),
          GoRoute(
            path: RouteNames.onboardingReligion,
            builder: (_, _) => const OnboardingReligionPage(),
          ),
          GoRoute(
            path: RouteNames.onboardingNameDob,
            builder: (_, _) => const Scaffold(body: Text('name-reached')),
          ),
          GoRoute(
            path: RouteNames.onboardingContact,
            builder: (_, _) => const Scaffold(body: Text('contact-reached')),
          ),
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

  ProviderContainer containerWith(
    FakeLocationRepository locations, {
    LocationDetails? location,
  }) {
    final container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider
            .overrideWithValue(RecordingRegistrationRepository()),
        ...locationOverrides(locations),
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
      ],
    );
    if (location != null) {
      container.read(registrationProvider.notifier).state = container
          .read(registrationProvider)
          .copyWith(locationDetails: location);
    }
    return container;
  }

  Finder countryField() => find.ancestor(
        of: find.text('Living in *'),
        matching: find.byType(LocationPickerField),
      );

  group('1. onboarding startup prefetches countries', () {
    testWidgets('the first onboarding screen warms the country list', (
      tester,
    ) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository();
      final container = containerWith(locations);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, onboardingRouter()));
      await tester.pumpAndSettle();

      // Two screens before the country is asked.
      expect(locations.countryRequests, 1);
    });

    testWidgets('it fetches nothing else — states and cities stay lazy', (
      tester,
    ) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository();
      final container = containerWith(locations);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, onboardingRouter()));
      await tester.pumpAndSettle();

      // Warming the whole hierarchy at boot is what PR #55 deliberately
      // stopped doing; this warms one list, not the tree.
      expect(locations.calls, ['countries']);
    });

    testWidgets('a failed prefetch is silent and breaks nothing', (
      tester,
    ) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository(failCountries: true);
      final container = containerWith(locations);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, onboardingRouter()));
      await tester.pumpAndSettle();

      // Nothing on this screen asked for a country, so a failure here must
      // not reach the member or the zone as an unhandled error.
      expect(tester.takeException(), isNull);
      expect(find.byType(CreateProfileForPage), findsOneWidget);
    });
  });

  group('2. the country field uses the prefetched data', () {
    testWidgets('opening the field issues no second request', (tester) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository();
      final container = containerWith(locations);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, onboardingRouter()));
      await tester.pumpAndSettle();
      expect(locations.countryRequests, 1, reason: 'prefetch');

      // Walk on to the screen that actually asks for the country.
      final router = GoRouter.of(
        tester.element(find.byType(CreateProfileForPage)),
      );
      router.go(RouteNames.onboardingReligion);
      await tester.pumpAndSettle();

      await tester.tap(countryField());
      await tester.pumpAndSettle();

      // The list is on screen, and it came from the warm provider.
      expect(find.text('Canada'), findsOneWidget);
      expect(
        locations.countryRequests,
        1,
        reason: 'the field must reuse the prefetched list, not re-request it',
      );
    });

    testWidgets('the list is resolved before the field is ever built', (
      tester,
    ) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository();
      final container = containerWith(locations);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, onboardingRouter()));
      await tester.pumpAndSettle();

      // The whole point of the warm-up, asserted on the provider the field
      // reads rather than on a frame of the route transition: by the time the
      // member reaches the country question the answer is already in hand, so
      // the field has nothing to wait for and shows no spinner.
      final countries = container.read(countriesProvider);
      expect(countries.isLoading, isFalse);
      expect(countries.hasValue, isTrue);
      expect(countries.requireValue.map((c) => c.code), ['IN', 'CA']);
    });
  });

  group('3. Basics still does not fetch countries needlessly', () {
    testWidgets('a draft carrying a country code costs no country request', (
      tester,
    ) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository();
      final container = containerWith(
        locations,
        location: const LocationDetails(country: 'India', countryCode: 'IN'),
      );
      addTearDown(container.dispose);

      // Straight onto Basics, skipping the prefetch, as a resumed session
      // reaching this step directly would.
      await tester.pumpWidget(
        harness(
          container,
          GoRouter(
            initialLocation: RouteNames.profileBasics,
            routes: [
              GoRoute(
                path: RouteNames.profileBasics,
                builder: (_, _) => const ProfileBasicsPage(),
              ),
              GoRoute(
                path: RouteNames.onboardingMarital,
                builder: (_, _) => const Scaffold(body: Text('m')),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(locations.countryRequests, 0);
      expect(locations.calls, contains('states:IN'));
    });

    testWidgets('the prefetch does not make Basics ask again either', (
      tester,
    ) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository();
      final container = containerWith(
        locations,
        location: const LocationDetails(country: 'India', countryCode: 'IN'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, onboardingRouter()));
      await tester.pumpAndSettle();

      final router = GoRouter.of(
        tester.element(find.byType(CreateProfileForPage)),
      );
      router.go(RouteNames.profileBasics);
      await tester.pumpAndSettle();

      // One request in total, from the prefetch — walking the flow must not
      // accumulate them.
      expect(locations.countryRequests, 1);
    });
  });

  group('4. no duplicate concurrent requests', () {
    testWidgets('a second caller during the flight joins the first request', (
      tester,
    ) async {
      useTallSurface(tester);
      // Held open, so the prefetch is genuinely still in flight when the
      // country field asks. Without the gate this would pass simply because
      // the first request finished in between, proving nothing.
      final locations = FakeLocationRepository(holdCountries: true);
      final container = containerWith(locations);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, onboardingRouter()));
      await tester.pump();
      expect(locations.countryRequests, 1, reason: 'prefetch, still in flight');

      final router = GoRouter.of(
        tester.element(find.byType(CreateProfileForPage)),
      );
      router.go(RouteNames.onboardingReligion);
      await tester.pump();

      // The field is now built and watching, while the first request has
      // still not returned.
      expect(
        locations.countryRequests,
        1,
        reason: 'the in-flight request must be shared, not duplicated',
      );

      // And once it lands, the field resolves from that same request.
      locations.releaseCountries();
      await tester.pumpAndSettle();
      expect(locations.countryRequests, 1);
      final field = tester.widget<LocationPickerField>(countryField());
      expect(field.options.hasValue, isTrue);
    });

    testWidgets('re-entering the first screen does not re-request', (
      tester,
    ) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository();
      final container = containerWith(locations);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, onboardingRouter()));
      await tester.pumpAndSettle();

      final router = GoRouter.of(
        tester.element(find.byType(CreateProfileForPage)),
      );
      // Every sign-up path lands on this screen, and a resumed registration
      // re-enters it, so repeat visits are the normal case rather than an
      // edge one.
      router.go(RouteNames.onboardingReligion);
      await tester.pumpAndSettle();
      router.go(RouteNames.createProfileFor);
      await tester.pumpAndSettle();
      router.go(RouteNames.createProfileFor);
      await tester.pumpAndSettle();

      expect(locations.countryRequests, 1);
    });
  });

  group('existing behaviour is preserved', () {
    testWidgets('a failed load still shows the error and a retry', (
      tester,
    ) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository(failCountries: true);
      final container = containerWith(
        locations,
        location: const LocationDetails(country: ''),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, onboardingRouter()));
      await tester.pumpAndSettle();

      final router = GoRouter.of(
        tester.element(find.byType(CreateProfileForPage)),
      );
      router.go(RouteNames.onboardingReligion);
      await tester.pumpAndSettle();

      // The prefetch failing must leave the field's own error handling
      // exactly as it was — visible, and recoverable.
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
