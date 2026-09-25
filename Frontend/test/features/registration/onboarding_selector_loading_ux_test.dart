import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/widgets/feedback/selection_list_skeleton.dart';
import 'package:nenjam_matrimony/core/widgets/indicators/nm_field_loader.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/location/presentation/providers/location_providers.dart';
import 'package:nenjam_matrimony/features/location/presentation/widgets/location_picker_field.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_religion_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_basics_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/features/religion/presentation/providers/religion_providers.dart';

import 'onboarding_test_support.dart';

/// The premium inline loading UX for State / City / Religion / Community:
/// a sheet that opens immediately and shows a skeleton + a contextual
/// message while its list loads, then a specific empty message, or an error
/// with its own retry — never a full-screen spinner, and never a sheet that
/// silently waits for the network before opening at all.
///
/// [onboarding_location_cascade_test.dart] and
/// [onboarding_religion_cascade_test.dart] already pin the cascade rules
/// (what loads when, staleness, codes vs. labels); these pin the loading
/// *presentation* layered on top of the same providers.
void main() {
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

  GoRouter religionRouter() => GoRouter(
        initialLocation: RouteNames.onboardingReligion,
        routes: [
          GoRoute(
            path: RouteNames.onboardingReligion,
            builder: (_, _) => const OnboardingReligionPage(),
          ),
          GoRoute(
            path: RouteNames.onboardingContact,
            builder: (_, _) => const SizedBox.shrink(),
          ),
        ],
      );

  ProviderContainer containerWith({
    FakeLocationRepository? locations,
    FakeReligionRepository? religions,
    LocationDetails? location,
  }) {
    final container = ProviderContainer(
      overrides: [
        ...locationOverrides(locations ?? FakeLocationRepository(), religions: religions),
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
      ],
    );
    if (location != null) {
      container.read(registrationProvider.notifier).state =
          container.read(registrationProvider).copyWith(locationDetails: location);
    }
    return container;
  }

  const inIndia = LocationDetails(country: 'India', countryCode: 'IN');

  /// A single frame, then a jump far enough past any modal transition's
  /// duration to land on its settled end state — WITHOUT `pumpAndSettle`.
  ///
  /// A field that is (deliberately, via a held fake) still loading shows an
  /// indeterminate spinner or shimmer, both driven by a repeating ticker that
  /// never stops on its own — `pumpAndSettle` waits for every ticker to go
  /// quiet, so it would spin until it times out the test. These tests
  /// instead advance the clock by a fixed, generous amount, which is enough
  /// for a bottom sheet's (finite) entrance/close transition but leaves the
  /// perpetual animation running, exactly as it would in the app.
  Future<void> pumpPastTransition(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Taps the field headed [label] and settles just the sheet's entrance
  /// transition — see [pumpPastTransition] for why this isn't `pumpAndSettle`.
  Future<void> openWhileLoading(WidgetTester tester, String label) async {
    await tester.tap(
      find.ancestor(of: find.text(label), matching: find.byType(LocationPickerField)),
    );
    await pumpPastTransition(tester);
  }

  /// [text] as drawn inside the open sheet, as opposed to the same message
  /// the field behind it shows in place of its hint while loading.
  Finder inSheet(String text) =>
      find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

  /// The field headed [label].
  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(LocationPickerField));

  /// Asserts nothing on screen — field, sheet or page — is drawing a stock
  /// Material/Cupertino spinner while one of these lists loads.
  void expectNoStockSpinner() {
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  }

  /// Asserts the field headed [label] shows the small trailing loader and
  /// [message] in place of its hint — and not its idle chevron or any stock
  /// spinner.
  void expectFieldLoading(
    WidgetTester tester,
    String label,
    String message,
  ) {
    expectNoStockSpinner();
    expect(
      find.descendant(of: field(label), matching: find.byType(NmFieldLoader)),
      findsOneWidget,
    );
    // The ring itself stays 18x18 — the suffix slot's 32x32 minimum must not
    // stretch it into a field-height spinner against the border.
    expect(
      tester.getSize(
        find.descendant(
          of: find.byType(NmFieldLoader),
          matching: find.byType(CustomPaint),
        ),
      ),
      const Size(18, 18),
    );
    expect(
      find.descendant(of: field(label), matching: find.text(message)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: field(label),
        matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
      ),
      findsNothing,
    );
  }

  /// Picks [option] from the field headed [label] without `pumpAndSettle` —
  /// for use right before a child field's fetch is held indefinitely by a
  /// test fake, where the resulting perpetual spinner would otherwise hang
  /// the settle that closing this sheet would normally do.
  Future<void> pickBounded(WidgetTester tester, String label, String option) async {
    await tester.tap(
      find.ancestor(of: find.text(label), matching: find.byType(LocationPickerField)),
    );
    await pumpPastTransition(tester);
    await tester.tap(find.widgetWithText(ListTile, option).last);
    await pumpPastTransition(tester);
  }

  // ─── State ──────────────────────────────────────────────────────────────

  group('State', () {
    testWidgets(
        'opens immediately and shows a skeleton with "Loading states..." '
        'while still loading', (tester) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository(holdStates: true);
      final container = containerWith(locations: locations, location: inIndia);
      addTearDown(container.dispose);

      // Not `pumpAndSettle`: the States fetch starts as soon as the page
      // builds, and it is held from the very first frame.
      await tester.pumpWidget(harness(container, basicsRouter()));
      await pumpPastTransition(tester);

      expectFieldLoading(tester, 'State *', 'Loading states...');

      await openWhileLoading(tester, 'State *');

      expect(inSheet('Loading states...'), findsOneWidget);
      // The sheet's own loading state is a skeleton, and the field behind it
      // keeps its NmFieldLoader — neither is a stock spinner.
      expectNoStockSpinner();
      expect(find.byType(NmFieldLoader), findsOneWidget);
      final skeleton = tester.widget<SelectionListSkeleton>(
        find.byType(SelectionListSkeleton),
      );
      expect(skeleton.rowCount, inInclusiveRange(3, 5));
      // No dimension has collapsed to zero and no real option is showing yet.
      expect(find.byType(ListTile), findsNothing);

      locations.releaseStates();
      await tester.pumpAndSettle();

      expect(find.byType(SelectionListSkeleton), findsNothing);
      expect(find.widgetWithText(ListTile, 'Gujarat'), findsOneWidget);
      // The loader leaves with the request, and the hint comes back.
      expect(find.byType(NmFieldLoader), findsNothing);
      expect(find.text('Loading states...'), findsNothing);
    });

    testWidgets('an empty state list shows its own message, not a blank sheet',
        (tester) async {
      useTallSurface(tester);
      // The fake only lists states for 'IN' — anything else resolves to an
      // empty (not failed) list.
      final container = containerWith(
        location: const LocationDetails(country: 'Australia', countryCode: 'AU'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.ancestor(of: find.text('State *'), matching: find.byType(LocationPickerField)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No states available'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(NmFieldLoader), findsNothing);
    });

    testWidgets(
        'a failed load offers its own retry, and a successful retry replaces '
        'it with the list — never stuck loading', (tester) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository(failStates: true);
      final container = containerWith(locations: locations, location: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.ancestor(of: find.text('State *'), matching: find.byType(LocationPickerField)),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load states"), findsOneWidget);
      // A failure never leaves the field spinning.
      expect(find.byType(NmFieldLoader), findsNothing);
      final retry = find.widgetWithText(TextButton, 'Retry');
      expect(retry, findsOneWidget);

      // The retry the member taps must actually fix the underlying request,
      // not just redraw the same failure.
      locations.failStates = false;
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load states"), findsNothing);
      expect(find.widgetWithText(ListTile, 'Gujarat'), findsOneWidget);
    });
  });

  // ─── City ───────────────────────────────────────────────────────────────

  group('City', () {
    testWidgets('is disabled with its own hint before a state is chosen',
        (tester) async {
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
      expect(city.disabledHint, 'State you live in');
    });

    testWidgets(
        'shows "Finding cities in <state>..." and a skeleton while its own '
        'state is loading', (tester) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository(holdCities: true);
      final container = containerWith(locations: locations, location: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      // Not `pickLocation`: picking Gujarat starts the (held) cities fetch,
      // and closing the State sheet with `pumpAndSettle` would then hang on
      // the City field's resulting perpetual spinner.
      await pickBounded(tester, 'State *', 'Gujarat');
      expectFieldLoading(tester, 'City *', 'Finding cities in Gujarat...');

      await openWhileLoading(tester, 'City *');

      expect(inSheet('Finding cities in Gujarat...'), findsOneWidget);
      // The sheet's own loading state is a skeleton, and the field behind it
      // keeps its NmFieldLoader — neither is a stock spinner.
      expectNoStockSpinner();
      expect(find.byType(NmFieldLoader), findsOneWidget);
      expect(find.byType(SelectionListSkeleton), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);

      locations.releaseCities();
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Bhavnagar'), findsOneWidget);
      expect(find.byType(NmFieldLoader), findsNothing);
    });

    testWidgets('an empty city list names the state it found nothing for',
        (tester) async {
      useTallSurface(tester);
      final container = ProviderContainer(
        overrides: [
          ...locationOverrides(FakeLocationRepository()),
          // Gujarat is a real, chosen state — its city list is what is empty.
          citiesProvider('IN-GJ').overrideWith((ref) async => const []),
        ],
      );
      container.read(registrationProvider.notifier).state =
          container.read(registrationProvider).copyWith(locationDetails: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      await pickLocation(tester, 'State *', 'Gujarat');
      await tester.tap(
        find.ancestor(of: find.text('City *'), matching: find.byType(LocationPickerField)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No cities found for this state'), findsOneWidget);
    });

    testWidgets(
        'a failed city load offers its own retry, and a successful retry '
        'replaces it with the list', (tester) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository(failCities: true);
      final container = containerWith(locations: locations, location: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      await pickLocation(tester, 'State *', 'Gujarat');
      await tester.tap(
        find.ancestor(of: find.text('City *'), matching: find.byType(LocationPickerField)),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load cities"), findsOneWidget);

      locations.failCities = false;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load cities"), findsNothing);
      expect(find.widgetWithText(ListTile, 'Bhavnagar'), findsOneWidget);
    });

    testWidgets(
        'switching state while cities are loading: the slow reply for the '
        'old state cannot overwrite the new one', (tester) async {
      useTallSurface(tester);
      final locations = FakeLocationRepository(
        cityDelay: const {'IN-GJ': Duration(seconds: 2)},
      );
      final container = containerWith(locations: locations, location: inIndia);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, basicsRouter()));
      await tester.pumpAndSettle();

      await pickLocation(tester, 'State *', 'Gujarat');
      await tester.pump(); // cities:IN-GJ is now in flight, unresolved.

      // Quickly switch away before Gujarat's slow reply lands.
      await pickLocation(tester, 'State *', 'Tamil Nadu');

      // Let the slow Gujarat response arrive.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await tester.tap(
        find.ancestor(of: find.text('City *'), matching: find.byType(LocationPickerField)),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Chennai'), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'Bhavnagar'),
        findsNothing,
        reason: 'the late Gujarat response must not replace the Tamil Nadu list',
      );
    });
  });

  // ─── Religion ───────────────────────────────────────────────────────────

  group('Religion', () {
    testWidgets('opens immediately and shows a skeleton with "Loading '
        'religions..." while still loading', (tester) async {
      useTallSurface(tester);
      final religions = FakeReligionRepository(holdReligions: true);
      final container = containerWith(religions: religions);
      addTearDown(container.dispose);

      // Not `pumpAndSettle`: the Religions fetch starts as soon as the page
      // builds, and it is held from the very first frame.
      await tester.pumpWidget(harness(container, religionRouter()));
      await pumpPastTransition(tester);

      expectFieldLoading(tester, 'Religion *', 'Loading religions...');

      await openWhileLoading(tester, 'Religion *');

      expect(inSheet('Loading religions...'), findsOneWidget);
      // The sheet's own loading state is a skeleton, and the field behind it
      // keeps its NmFieldLoader — neither is a stock spinner.
      expectNoStockSpinner();
      expect(find.byType(NmFieldLoader), findsOneWidget);
      expect(find.byType(SelectionListSkeleton), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);

      religions.releaseReligions();
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Hindu'), findsOneWidget);
      expect(find.byType(NmFieldLoader), findsNothing);
    });

    testWidgets(
        'a failed load offers its own retry, and a successful retry replaces '
        'it with the list', (tester) async {
      useTallSurface(tester);
      final religions = FakeReligionRepository(failReligions: true);
      final container = containerWith(religions: religions);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.ancestor(of: find.text('Religion *'), matching: find.byType(LocationPickerField)),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load religions"), findsOneWidget);

      religions.failReligions = false;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load religions"), findsNothing);
      expect(find.widgetWithText(ListTile, 'Hindu'), findsOneWidget);
    });
  });

  // ─── Community ──────────────────────────────────────────────────────────

  group('Community', () {
    testWidgets('is disabled with its own hint before a religion is chosen',
        (tester) async {
      useTallSurface(tester);
      final container = containerWith();
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      final community = tester.widget<LocationPickerField>(
        find.ancestor(
          of: find.text('Community *'),
          matching: find.byType(LocationPickerField),
        ),
      );
      expect(community.enabled, isFalse);
    });

    testWidgets('shows a skeleton with "Loading communities..." while still '
        'loading', (tester) async {
      useTallSurface(tester);
      final religions = FakeReligionRepository(holdCommunities: true);
      final container = containerWith(religions: religions);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      // Not `pickLocation`: picking Hindu starts the (held) communities
      // fetch, and closing the Religion sheet with `pumpAndSettle` would then
      // hang on the Community field's resulting perpetual spinner.
      await pickBounded(tester, 'Religion *', 'Hindu');
      expectFieldLoading(tester, 'Community *', 'Loading communities...');

      await openWhileLoading(tester, 'Community *');

      expect(inSheet('Loading communities...'), findsOneWidget);
      // The sheet's own loading state is a skeleton, and the field behind it
      // keeps its NmFieldLoader — neither is a stock spinner.
      expectNoStockSpinner();
      expect(find.byType(NmFieldLoader), findsOneWidget);
      expect(find.byType(SelectionListSkeleton), findsOneWidget);

      religions.releaseCommunities();
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Iyer'), findsOneWidget);
      expect(find.byType(NmFieldLoader), findsNothing);
    });

    testWidgets('an empty community list says so', (tester) async {
      useTallSurface(tester);
      final container = ProviderContainer(
        overrides: [
          ...locationOverrides(FakeLocationRepository()),
          // Hindu is a real, chosen religion — its community list is what is
          // empty here.
          communitiesProvider('HINDU').overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      await pickLocation(tester, 'Religion *', 'Hindu');
      await tester.tap(
        find.ancestor(of: find.text('Community *'), matching: find.byType(LocationPickerField)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No communities found'), findsOneWidget);
    });

    testWidgets(
        'a failed load offers its own retry, and a successful retry replaces '
        'it with the list', (tester) async {
      useTallSurface(tester);
      final religions = FakeReligionRepository(failCommunities: true);
      final container = containerWith(religions: religions);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      await pickLocation(tester, 'Religion *', 'Hindu');
      await tester.tap(
        find.ancestor(of: find.text('Community *'), matching: find.byType(LocationPickerField)),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load communities"), findsOneWidget);

      religions.failCommunities = false;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load communities"), findsNothing);
      expect(find.widgetWithText(ListTile, 'Iyer'), findsOneWidget);
    });

    testWidgets(
        'switching religion while communities are loading: the slow reply '
        'for the old religion cannot overwrite the new one', (tester) async {
      useTallSurface(tester);
      final religions = FakeReligionRepository(
        communityDelay: const {'HINDU': Duration(seconds: 2)},
      );
      final container = containerWith(religions: religions);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, religionRouter()));
      await tester.pumpAndSettle();

      await pickLocation(tester, 'Religion *', 'Hindu');
      await tester.pump(); // communities:HINDU is now in flight, unresolved.

      await pickLocation(tester, 'Religion *', 'Jain');

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await tester.tap(
        find.ancestor(of: find.text('Community *'), matching: find.byType(LocationPickerField)),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Digambar'), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'Iyer'),
        findsNothing,
        reason: 'the late Hindu response must not replace the Jain list',
      );
    });
  });
}
