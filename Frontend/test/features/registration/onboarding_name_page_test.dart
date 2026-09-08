import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/utils/birth_date.dart';
import 'package:nenjam_matrimony/core/widgets/inputs/birth_date_field.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/onboarding_forms.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_name_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// The second onboarding screen: **first name, last name and a date of birth
/// typed as DD / MM / YYYY are all required, and answering them opens the
/// Religion step.**
///
/// All three are NOT NULL columns on `user_profiles` and all three land on
/// `BasicDetails`, so this screen is what lets `isMatchableFromDraft` pass and
/// the backend write a profile row at all. They used to be asked on Profile
/// Basics, beside the state and city pickers; nothing about where they are
/// stored changed when they moved here, and nothing changed again when the
/// calendar became three typed boxes — `BasicDetails.dob` is the same
/// `DateTime`, now serialized as the date-only `YYYY-MM-DD` the API takes.
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

  /// The three date boxes, in the order they read across the row.
  Finder dobBoxes() => find.descendant(
        of: find.byType(NmBirthDateField),
        matching: find.byType(TextFormField),
      );

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
    await enterDob(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('religion-reached'), findsNothing);

    // Both names plus the date already typed: now it opens.
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

    final typed = await fillNameStep(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final basic = container.read(registrationProvider).basicDetails;
    expect(basic.firstName, 'Arjun');
    expect(basic.lastName, 'Krishnan');
    expect(basic.dob, typed);

    // Onboarding has no later step that syncs this section for it, so the
    // answers must reach the backend here — otherwise the gate in
    // PostAuthDestination sends the member straight back.
    expect(repository.savedSections, contains('basicDetails'));
    expect(repository.savedBasic?.firstName, 'Arjun');
    expect(repository.savedBasic?.lastName, 'Krishnan');
    expect(repository.savedBasic?.dob, typed);
    // And in the shape the API takes: a date-only `YYYY-MM-DD` on
    // `basicDetails.dob`. A birthdate is a calendar date, and sending it as a
    // timestamp is what let the stored value drift a day either side of
    // midnight.
    expect(repository.savedBasic?.toJson()['dob'], '1998-08-15');

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

  // ─── The date of birth, typed ───────────────────────────────────────
  //
  // The step used to open a calendar. A member who knows their own date of
  // birth types it faster than they can scroll to it, and someone creating a
  // profile for a son or a sister has to scroll further still — so the boxes
  // take keystrokes and the rule, which the calendar used to enforce by
  // omission, is stated and enforced instead.

  group('the date of birth boxes', () {
    testWidgets('accept a typed DD / MM / YYYY', (tester) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
      // The format is said once, above the row, rather than left to be
      // discovered by getting it wrong.
      expect(find.text('Enter it as DD / MM / YYYY.'), findsOneWidget);

      await enterDob(tester, DateTime(1998, 8, 15));

      await tester.enterText(find.byType(TextFormField).at(0), 'Arjun');
      await tester.enterText(find.byType(TextFormField).at(1), 'Krishnan');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(
        container.read(registrationProvider).basicDetails.dob,
        DateTime(1998, 8, 15),
      );
    });

    testWidgets('take digits only, and no more than the box holds', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      // A pasted "15/08" and a mistyped letter never reach the rule as
      // something it has to explain.
      await tester.enterText(dobBoxes().at(0), '1a5/');
      await tester.enterText(dobBoxes().at(2), '19988');
      await tester.pumpAndSettle();

      expect(tester.widget<TextFormField>(dobBoxes().at(0)).controller?.text,
          '15');
      expect(tester.widget<TextFormField>(dobBoxes().at(2)).controller?.text,
          '1998');
    });

    testWidgets('say what is wrong, and Continue stays shut', (tester) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Arjun');
      await tester.enterText(find.byType(TextFormField).at(1), 'Krishnan');

      // 31 February is three plausible numbers that name no day.
      await enterDob(tester, null);
      await tester.enterText(dobBoxes().at(0), '31');
      await tester.enterText(dobBoxes().at(1), '02');
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid date of birth.'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('religion-reached'), findsNothing);

      // Month 13.
      await tester.enterText(dobBoxes().at(1), '13');
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid month.'), findsOneWidget);

      // Day 00.
      await tester.enterText(dobBoxes().at(0), '00');
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid date.'), findsOneWidget);

      // Under 21.
      await enterDob(tester, DateTime(DateTime.now().year - 10, 8, 15));
      expect(
        find.text('You must be at least 21 years old to register.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('religion-reached'), findsNothing);

      // And a real, allowed date clears it.
      await enterDob(tester, DateTime(1998, 8, 15));
      expect(find.textContaining('Please enter'), findsNothing);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('religion-reached'), findsOneWidget);
    });

    testWidgets('stay quiet while a box is still being typed', (tester) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      // "1" on its way to "15", "199" on its way to "1998" — nothing wrong
      // yet, so nothing said yet.
      await tester.enterText(dobBoxes().at(0), '1');
      await tester.enterText(dobBoxes().at(1), '0');
      await tester.enterText(dobBoxes().at(2), '199');
      await tester.pumpAndSettle();
      expect(find.textContaining('Please enter'), findsNothing);
    });

    testWidgets('hand focus on as each box fills', (tester) async {
      useTallSurface(tester);
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();

      bool hasFocus(int box) => tester
          .widget<EditableText>(
            find.descendant(
              of: dobBoxes().at(box),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus;

      await tester.tap(dobBoxes().at(0));
      await tester.pumpAndSettle();
      await tester.enterText(dobBoxes().at(0), '15');
      await tester.pumpAndSettle();

      // Two digits is a whole day, so the member's next keystroke belongs to
      // the month without them reaching for it.
      expect(hasFocus(1), isTrue);

      await tester.enterText(dobBoxes().at(1), '08');
      await tester.pumpAndSettle();
      expect(hasFocus(2), isTrue);
    });

    testWidgets('reopen on the date already answered', (tester) async {
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

      // Zero-padded, the way the member would have typed it.
      expect(find.text('21'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);
      expect(find.text('1995'), findsOneWidget);
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
    expect(find.text('15'), findsOneWidget);
    expect(find.text('08'), findsOneWidget);
    expect(find.text('1998'), findsOneWidget);
  });

  // ─── The rule itself ────────────────────────────────────────────────
  //
  // PostAuthDestination reconstructs this same form to decide whether to
  // re-ask the step, so the rule is asserted directly and not only through
  // the screen. `BirthDateInput` owns it — see birth_date_test.dart for the
  // full table of dates; these are the cases the form has to carry through.

  group('OnboardingNameForm', () {
    test('parses a real date', () {
      const form = OnboardingNameForm(
        firstName: 'Arjun',
        lastName: 'Krishnan',
        birthDate: BirthDateInput(day: '05', month: '02', year: '1998'),
      );
      expect(form.dob, DateTime(1998, 2, 5));
      expect(form.isComplete, isTrue);
    });

    test('rejects a rolled-over date rather than accepting the rollover', () {
      const form = OnboardingNameForm(
        birthDate: BirthDateInput(day: '31', month: '02', year: '2003'),
      );
      expect(form.dob, isNull);
      expect(form.dateError, BirthDateError.invalidDate);
    });

    test('applies no upper bound on age', () {
      const form = OnboardingNameForm(
        firstName: 'Arjun',
        lastName: 'Krishnan',
        birthDate: BirthDateInput(day: '05', month: '02', year: '1900'),
      );
      expect(form.dob, DateTime(1900, 2, 5));
      expect(form.dateError, isNull);
      expect(form.isComplete, isTrue);
    });

    test('rejects a date in the future', () {
      final form = OnboardingNameForm(
        birthDate: BirthDateInput(
          day: '05',
          month: '02',
          year: '${DateTime.now().year + 1}',
        ),
      );
      expect(form.dob, isNull);
      expect(form.dateError, BirthDateError.future);
    });

    test('rejects anyone under 21', () {
      final form = OnboardingNameForm(
        birthDate: BirthDateInput(
          day: '05',
          month: '02',
          year: '${DateTime.now().year - 10}',
        ),
      );
      expect(form.dob, isNull);
      expect(form.dateError, BirthDateError.tooYoung);
    });

    test('fromDraft round-trips a stored date into the three boxes', () {
      final form = OnboardingNameForm.fromDraft(
        firstName: 'Meera',
        lastName: 'Rajan',
        dob: DateTime(1995, 3, 21),
      );
      // Zero-padded, because that is how the member typed it — the two have
      // to agree or a resumed step would look edited.
      expect(form.birthDate.day, '21');
      expect(form.birthDate.month, '03');
      expect(form.birthDate.year, '1995');
      expect(form.dob, DateTime(1995, 3, 21));
      expect(form.isComplete, isTrue);
    });

    test('is answered, but not complete, for a member under the new floor',
        () {
      // What routing asks of an existing member who registered when the floor
      // was 18. `isComplete` still refuses — the screen cannot let them save a
      // date the server would reject — but `isAnswered` is what
      // PostAuthDestination gates on, so they are not sent back to a step no
      // answer of theirs can satisfy.
      final form = OnboardingNameForm.fromDraft(
        firstName: 'Meera',
        lastName: 'Rajan',
        dob: DateTime(DateTime.now().year - 19, 3, 21),
      );
      expect(form.isAnswered, isTrue);
      expect(form.isComplete, isFalse);
      expect(form.dateError, BirthDateError.tooYoung);
    });

    test('is neither answered nor complete without a date', () {
      final form = OnboardingNameForm.fromDraft(
        firstName: 'Meera',
        lastName: 'Rajan',
      );
      expect(form.isAnswered, isFalse);
      expect(form.isComplete, isFalse);
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
