import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/onboarding_forms.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_name_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// The second onboarding screen: **first name, last name and a typed date of
/// birth are all required, and answering them opens the Religion step.**
///
/// All three are NOT NULL columns on `user_profiles` and all three land on
/// `BasicDetails`, so this screen is what lets `isMatchableFromDraft` pass and
/// the backend write a profile row at all. They used to be asked on Profile
/// Basics, beside the state and city pickers; nothing about where they are
/// stored changed when they moved here.
void main() {
  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: RouteNames.onboardingNameDob,
      routes: [
        GoRoute(
          path: RouteNames.onboardingNameDob,
          builder: (context, state) => const OnboardingNamePage(),
        ),
        GoRoute(
          path: RouteNames.onboardingReligion,
          builder: (context, state) =>
              const Scaffold(body: Text('religion-reached')),
        ),
        GoRoute(
          path: RouteNames.createProfileFor,
          builder: (context, state) =>
              const Scaffold(body: Text('profile-for-reached')),
        ),
      ],
    );
  }

  ProviderContainer containerWith(RecordingRegistrationRepository repository) {
    return ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
        // Onboarding persists to the backend only with a session; without
        // this the step would write locally and the repository would never
        // be called.
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
      ],
    );
  }

  // ─── Continue gating ────────────────────────────────────────────────

  testWidgets('Continue stays inert until all three answers are given', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('religion-reached'), findsNothing);

    // A name without a date of birth is not an answer — `dob` is NOT NULL.
    await tester.enterText(find.byType(TextFormField).at(0), 'Arjun');
    await tester.enterText(find.byType(TextFormField).at(1), 'Krishnan');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('religion-reached'), findsNothing);

    // Nor is a date of birth without a last name.
    await tester.enterText(find.byType(TextFormField).at(1), '');
    await enterDob(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('religion-reached'), findsNothing);
    expect(container.read(registrationProvider).basicDetails.dob, isNull);
  });

  testWidgets('answering all three writes the draft, persists, and opens '
      'Religion', (tester) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await fillNameStep(tester, day: '05', month: '02', year: '2003');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final basic = container.read(registrationProvider).basicDetails;
    expect(basic.firstName, 'Arjun');
    expect(basic.lastName, 'Krishnan');
    expect(basic.dob, DateTime(2003, 2, 5));

    // Onboarding has no later step that syncs this section for it, so the
    // answers must reach the backend here — otherwise the gate in
    // PostAuthDestination sends the member straight back.
    expect(repository.savedSections, contains('basicDetails'));
    expect(repository.savedBasic?.firstName, 'Arjun');
    expect(repository.savedBasic?.lastName, 'Krishnan');
    expect(repository.savedBasic?.dob, DateTime(2003, 2, 5));

    expect(find.text('religion-reached'), findsOneWidget);
  });

  testWidgets('the name is stored trimmed', (tester) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await fillNameStep(tester, firstName: '  Arjun ', lastName: ' Krishnan  ');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // `first_name` is what every Discover card renders; a leading space is a
    // typo, not part of someone's name.
    expect(repository.savedBasic?.firstName, 'Arjun');
    expect(repository.savedBasic?.lastName, 'Krishnan');
  });

  // ─── Date validation ────────────────────────────────────────────────

  group('the typed date of birth', () {
    testWidgets('rejects a day that does not exist in that month', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      // DateTime(2003, 2, 31) is 3 March, not an error — so a plain
      // constructor call would have silently accepted a date nobody typed.
      await fillNameStep(tester, day: '31', month: '02', year: '2003');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('religion-reached'), findsNothing);
      expect(find.text('Enter a real date of birth.'), findsOneWidget);
    });

    testWidgets('rejects 29 February in a common year', (tester) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      await fillNameStep(tester, day: '29', month: '02', year: '2003');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('religion-reached'), findsNothing);

      // The same day in a leap year is fine.
      await enterDob(tester, day: '29', month: '02', year: '2004');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('religion-reached'), findsOneWidget);
    });

    testWidgets('rejects a future date', (tester) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      final nextYear = DateTime.now().year + 1;
      await fillNameStep(tester, day: '05', month: '02', year: '$nextYear');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('religion-reached'), findsNothing);
      expect(container.read(registrationProvider).basicDetails.dob, isNull);
    });

    testWidgets('rejects anyone under 18', (tester) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      final tooRecent = DateTime.now().year - 10;
      await fillNameStep(tester, day: '05', month: '02', year: '$tooRecent');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('religion-reached'), findsNothing);
      expect(
        find.text('You must be at least 18 to create a profile.'),
        findsOneWidget,
      );
    });

    testWidgets('stays quiet while the member is still typing', (tester) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      // `05 / 02 / 200` is a half-typed year, not a mistake to scold about.
      await fillNameStep(tester, day: '05', month: '02', year: '200');
      expect(find.text('Enter a real date of birth.'), findsNothing);
      expect(find.text('Please check the year of birth.'), findsNothing);
    });

    testWidgets('the boxes accept digits only', (tester) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(2), 'ab');
      await tester.pumpAndSettle();
      // Nothing typed reaches the form, so the date is still unanswered
      // rather than a string that has to be defended against downstream.
      expect(find.text('ab'), findsNothing);
    });
  });

  // ─── Resume and failure ─────────────────────────────────────────────

  testWidgets('the screen reopens on the answers already in the draft', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);
    // What PostAuthDestination rehydrates before sending a returning member
    // here, and what Back from the Religion step leaves in place.
    container.read(registrationProvider.notifier).restore(
          ProfileDraft(
            basicDetails: BasicDetails(
              firstName: 'Meera',
              lastName: 'Rajan',
              dob: DateTime(1995, 3, 21),
            ),
          ),
          ProfileFlowMode.create,
        );

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    expect(find.text('Meera'), findsOneWidget);
    expect(find.text('Rajan'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.text('1995'), findsOneWidget);

    // All restored, so Continue is live on arrival and carries the stored
    // values through unchanged.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      container.read(registrationProvider).basicDetails.dob,
      DateTime(1995, 3, 21),
    );
    expect(find.text('religion-reached'), findsOneWidget);
  });

  testWidgets('a failed save keeps the member here with the form intact', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = _FailingBasicRepository();
    final container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    await fillNameStep(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Advancing on a failed save would only bounce them back on the next
    // launch, because the gate reads the backend's copy.
    expect(find.text('religion-reached'), findsNothing);
    // And nothing they typed is lost — the answers are still on screen, so a
    // retry is one tap rather than a retype.
    expect(find.text('Arjun'), findsOneWidget);
    expect(find.text('Krishnan'), findsOneWidget);
    expect(find.text('1998'), findsOneWidget);
  });

  // ─── The rule itself ────────────────────────────────────────────────
  //
  // PostAuthDestination reconstructs this same form to decide whether to
  // re-ask the step, so the rule is asserted directly and not only through
  // the screen.

  group('OnboardingNameForm', () {
    test('parses a real date', () {
      const form = OnboardingNameForm(
        firstName: 'Arjun',
        lastName: 'Krishnan',
        day: '5',
        month: '2',
        year: '1998',
      );
      expect(form.dob, DateTime(1998, 2, 5));
      expect(form.isComplete, isTrue);
    });

    test('rejects a rolled-over date rather than accepting the rollover', () {
      const form = OnboardingNameForm(day: '31', month: '02', year: '2003');
      expect(form.dob, isNull);
      expect(form.dateError, OnboardingNameDateError.invalid);
    });

    test('rejects a year before 1950', () {
      const form = OnboardingNameForm(day: '05', month: '02', year: '1900');
      expect(form.dob, isNull);
      expect(form.dateError, OnboardingNameDateError.tooOld);
    });

    test('fromDraft round-trips a stored date into the three boxes', () {
      final form = OnboardingNameForm.fromDraft(
        firstName: 'Meera',
        lastName: 'Rajan',
        dob: DateTime(1995, 3, 21),
      );
      expect(form.day, '21');
      expect(form.month, '03');
      expect(form.year, '1995');
      expect(form.dob, DateTime(1995, 3, 21));
      expect(form.isComplete, isTrue);
    });

    test('fromDraft on an unanswered draft is incomplete, not crashing', () {
      final form = OnboardingNameForm.fromDraft(firstName: '', lastName: '');
      expect(form.isComplete, isFalse);
      expect(form.missingFields, hasLength(3));
      // Nothing typed, so nothing to complain about yet.
      expect(form.dateError, isNull);
    });
  });
}

/// Fails only the basic-details save — the one call this step makes.
class _FailingBasicRepository extends RecordingRegistrationRepository {
  @override
  Future<void> updateBasicDetails(
    BasicDetails details, {
    bool skipMaterialize = false,
  }) async {
    throw Exception('basic details save failed');
  }
}
