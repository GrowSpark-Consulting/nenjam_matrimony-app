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

/// The second onboarding screen: **first name, last name and a date of birth
/// picked from the calendar are all required, and answering them opens the
/// Religion step.**
///
/// All three are NOT NULL columns on `user_profiles` and all three land on
/// `BasicDetails`, so this screen is what lets `isMatchableFromDraft` pass and
/// the backend write a profile row at all. They used to be asked on Profile
/// Basics, beside the state and city pickers; nothing about where they are
/// stored changed when they moved here, and nothing changed again when the
/// three Day/Month/Year boxes became one calendar — `BasicDetails.dob` is the
/// same `DateTime`, serialized by the same `toIso8601String`.
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
    expect(container.read(registrationProvider).basicDetails.dob, isNull);

    // Nor is a date of birth without a last name.
    await tester.enterText(find.byType(TextFormField).at(1), '');
    await pickDob(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('religion-reached'), findsNothing);

    // Both names plus the date the member already picked: now it opens.
    await tester.enterText(find.byType(TextFormField).at(1), 'Krishnan');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('religion-reached'), findsOneWidget);
  });

  testWidgets('answering all three writes the draft, persists, and opens '
      'Religion', (tester) async {
    useTallSurface(tester);
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    final picked = await fillNameStep(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final basic = container.read(registrationProvider).basicDetails;
    expect(basic.firstName, 'Arjun');
    expect(basic.lastName, 'Krishnan');
    expect(basic.dob, picked);

    // Onboarding has no later step that syncs this section for it, so the
    // answers must reach the backend here — otherwise the gate in
    // PostAuthDestination sends the member straight back.
    expect(repository.savedSections, contains('basicDetails'));
    expect(repository.savedBasic?.firstName, 'Arjun');
    expect(repository.savedBasic?.lastName, 'Krishnan');
    expect(repository.savedBasic?.dob, picked);
    // And in the shape the API has always been sent: an ISO-8601 string on
    // `basicDetails.dob`. The calendar changed how the date is asked for,
    // not what is stored or transmitted.
    expect(
      repository.savedBasic?.toJson()['dob'],
      picked.toIso8601String(),
    );

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

  // ─── The date of birth, picked rather than typed ────────────────────
  //
  // The step used to ask for Day, Month and Year in three boxes and reject
  // what came back. The calendar is the same rule stated as an affordance:
  // what it cannot offer, the member cannot answer wrongly.

  group('the date of birth calendar', () {
    testWidgets('opens from the field and writes the date back in words', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      // Nothing typed: the field is a prompt to tap.
      expect(find.text('Select your date of birth'), findsOneWidget);

      await openDobPicker(tester);
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Read back as a person says it, not as DD/MM/YYYY.
      final year = defaultDobMonth().year;
      expect(find.text('15 January $year'), findsOneWidget);
      // (The hint stays in the tree behind the value, faded out by
      // InputDecorator, so it is the value that is asserted on.)
    });

    testWidgets('opens from a tap on the calendar icon as well', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      // The icon is a hint, not a button — the whole field is the target,
      // which is what a member's thumb assumes.
      await tester.tap(find.byIcon(Icons.calendar_today_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('cannot offer a future date, or one under 18, or one before '
        '1950', (tester) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();
      await openDobPicker(tester);

      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      // Bounded by the form's own rule rather than a second copy of it, so
      // every date the calendar offers is one `OnboardingNameForm` accepts —
      // and every date it rejects is unreachable.
      expect(dialog.firstDate, OnboardingNameForm.earliestAllowedDob());
      expect(dialog.lastDate, OnboardingNameForm.latestAllowedDob());
      // Which puts today, and everything after it, out of reach.
      expect(dialog.lastDate.isBefore(DateTime.now()), isTrue);
      expect(
        const OnboardingNameForm().withDob(dialog.lastDate).dob,
        dialog.lastDate,
        reason: 'the newest date the calendar offers must still validate',
      );
    });

    testWidgets('opens on the date already answered', (tester) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);
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
      await openDobPicker(tester);

      // Changing a stored date starts from that date, not from a default
      // twenty-five years ago — the member is correcting an answer.
      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(dialog.initialDate, DateTime(1995, 3, 21));
    });

    testWidgets('dismissing the calendar leaves the answer alone', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      final picked = await pickDob(tester);
      await openDobPicker(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final year = defaultDobMonth().year;
      expect(find.text('15 January $year'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Arjun');
      await tester.enterText(find.byType(TextFormField).at(1), 'Krishnan');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(container.read(registrationProvider).basicDetails.dob, picked);
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
    expect(find.text('21 March 1995'), findsOneWidget);

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
    // And nothing they answered is lost — it is all still on screen, so a
    // retry is one tap rather than a re-entry.
    expect(find.text('Arjun'), findsOneWidget);
    expect(find.text('Krishnan'), findsOneWidget);
    expect(find.text('15 January ${defaultDobMonth().year}'), findsOneWidget);
  });

  // ─── The rule itself ────────────────────────────────────────────────
  //
  // PostAuthDestination reconstructs this same form to decide whether to
  // re-ask the step, so the rule is asserted directly and not only through
  // the screen. The calendar cannot produce most of these any more; the form
  // still has to reject them, because a draft restored from the backend can.

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

    test('rejects a date in the future', () {
      final form = OnboardingNameForm(
        day: '05',
        month: '02',
        year: '${DateTime.now().year + 1}',
      );
      expect(form.dob, isNull);
      expect(form.dateError, OnboardingNameDateError.tooYoung);
    });

    test('rejects anyone under 18', () {
      final form = OnboardingNameForm(
        day: '05',
        month: '02',
        year: '${DateTime.now().year - 10}',
      );
      expect(form.dob, isNull);
      expect(form.dateError, OnboardingNameDateError.tooYoung);
    });

    test('withDob round-trips the date the calendar returned', () {
      final form = const OnboardingNameForm(
        firstName: 'Arjun',
        lastName: 'Krishnan',
      ).withDob(DateTime(1998, 2, 5));
      // Zero-padded, because that is how `fromDraft` writes a stored date —
      // the two have to agree or a resumed step would look edited.
      expect(form.day, '05');
      expect(form.month, '02');
      expect(form.year, '1998');
      expect(form.dob, DateTime(1998, 2, 5));
      expect(form.isComplete, isTrue);
    });

    test('the calendar bounds are the form bounds', () {
      final latest = OnboardingNameForm.latestAllowedDob();
      expect(const OnboardingNameForm().withDob(latest).dob, latest);
      // A day past the bound is exactly what the calendar disables.
      expect(
        const OnboardingNameForm()
            .withDob(latest.add(const Duration(days: 1)))
            .dob,
        isNull,
      );
      expect(
        OnboardingNameForm.earliestAllowedDob().year,
        OnboardingNameForm.earliestBirthYear,
      );
    });

    test('fromDraft round-trips a stored date into the three parts', () {
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
      // Nothing answered, so nothing to complain about yet.
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
