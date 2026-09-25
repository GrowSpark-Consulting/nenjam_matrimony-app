import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/core/widgets/buttons/outlined_button.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/personality_result.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/quiz_question.dart';
import 'package:nenjam_matrimony/features/psychology/presentation/pages/psychology_quiz_page.dart';
import 'package:nenjam_matrimony/features/psychology/presentation/providers/personality_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'psychology_test_support.dart';

/// Past the fixtures' retake hint (completedAt Sep 20 + 7 days = Sep 27).
final _afterHint = DateTime.utc(2026, 10, 1, 12);

/// Inside the fixtures' retake hint window.
final _insideHint = DateTime.utc(2026, 9, 24, 12);

Future<void> _pump(
  WidgetTester tester,
  FakePersonalityRepository repo, {
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
  DateTime? now,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Nested under '/' so the page's Done button has something to pop to.
  final router = GoRouter(
    initialLocation: '/quiz',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('home')),
        routes: [
          GoRoute(path: 'quiz', builder: (_, __) => const PsychologyQuizPage()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalityRepositoryProvider.overrideWithValue(repo),
        psychologyClockProvider.overrideWithValue(() => now ?? _afterHint),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _start(WidgetTester tester, {String label = 'Start Quiz'}) async {
  // On short screens the intro scrolls, so the button may be below the fold.
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Finder _option(String key) => find.byKey(ValueKey('psychology-option-$key'));

Future<void> _choose(WidgetTester tester, String key) async {
  await tester.ensureVisible(_option(key));
  await tester.tap(_option(key));
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('intro no longer claims an OCEAN / Big-Five assessment', (
    tester,
  ) async {
    await _pump(tester, FakePersonalityRepository());
    expect(find.text('Start Quiz'), findsOneWidget);
    expect(find.textContaining('OCEAN'), findsNothing);
    expect(find.textContaining('Big'), findsNothing);
  });

  testWidgets('renders the backend question and its four option labels', (
    tester,
  ) async {
    await _pump(tester, FakePersonalityRepository());
    await _start(tester);

    expect(find.text('Question 1 of 3'), findsOneWidget);
    expect(find.text('Question 1 text?'), findsOneWidget);
    for (final key in ['A', 'B', 'C', 'D']) {
      expect(find.text('Q1 option $key'), findsOneWidget);
    }
    expect(find.text('Strongly Agree'), findsNothing);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsNWidgets(4));
  });

  testWidgets('selecting an option marks it checked and enables Next', (
    tester,
  ) async {
    await _pump(tester, FakePersonalityRepository());
    await _start(tester);

    // Next does nothing before an answer is chosen.
    await _tapButton(tester, 'Next');
    expect(find.text('Question 1 of 3'), findsOneWidget);

    await _choose(tester, 'C');
    expect(
      find.descendant(
        of: _option('C'),
        matching: find.byIcon(Icons.radio_button_checked_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);

    await _tapButton(tester, 'Next');
    expect(find.text('Question 2 of 3'), findsOneWidget);
    expect(find.text('Q2 option A'), findsOneWidget);
  });

  testWidgets('Back returns to the previous question with its answer kept', (
    tester,
  ) async {
    await _pump(tester, FakePersonalityRepository());
    await _start(tester);
    await _choose(tester, 'B');
    await _tapButton(tester, 'Next');
    expect(find.text('Back'), findsOneWidget);

    await _tapButton(tester, 'Back');
    expect(find.text('Question 1 of 3'), findsOneWidget);
    expect(
      find.descendant(
        of: _option('B'),
        matching: find.byIcon(Icons.radio_button_checked_rounded),
      ),
      findsOneWidget,
    );
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets(
      'long option labels wrap without overflow at ${width.toInt()}dp',
      (tester) async {
        await _pump(
          tester,
          FakePersonalityRepository(quiz: Quiz.fromJson(longLabelQuizJson())),
          size: Size(width, 640),
        );
        await _start(tester);

        expect(tester.takeException(), isNull);
        // The last option is reachable by scrolling and selectable.
        await _choose(tester, 'D');
        expect(tester.takeException(), isNull);
        expect(find.text('Submit'), findsOneWidget);
      },
    );
  }

  testWidgets('long labels also fit in Tamil at 320dp', (tester) async {
    await _pump(
      tester,
      FakePersonalityRepository(quiz: Quiz.fromJson(longLabelQuizJson())),
      size: const Size(320, 568),
      locale: const Locale('ta'),
    );
    await _start(tester, label: 'தேர்வைத் தொடங்கு');
    await _choose(tester, 'A');
    expect(tester.takeException(), isNull);
  });

  testWidgets('submit shows loading, then the completed state with answers', (
    tester,
  ) async {
    final repo = FakePersonalityRepository()..submitGate = Completer<void>();
    await _pump(tester, repo);
    await _start(tester);
    await _choose(tester, 'B');
    await _tapButton(tester, 'Next');
    await _choose(tester, 'C');
    await _tapButton(tester, 'Next');
    await _choose(tester, 'A');
    // The spinner animates until the backend answers, so no pumpAndSettle.
    await tester.tap(find.text('Submit'));
    await tester.pump();

    // Still waiting on the backend: loading, not yet completed.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Quiz completed'), findsNothing);

    repo.submitGate!.complete();
    await tester.pumpAndSettle();

    expect(repo.submits.single.answers, {'q1': 'B', 'q2': 'C', 'q3': 'A'});
    expect(find.text('Quiz completed'), findsOneWidget);
    expect(find.text('Your answers'), findsOneWidget);
    expect(find.text('Question 2 text?'), findsOneWidget);
    expect(find.text('Q2 option C'), findsOneWidget);
    expect(find.text('Retake Quiz'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('Openness'), findsNothing);
  });

  testWidgets('a failed submit is visible, keeps answers, and can be retried', (
    tester,
  ) async {
    final repo = FakePersonalityRepository()
      ..submitError = Exception('timeout');
    await _pump(tester, repo);
    await _start(tester);
    for (final key in ['A', 'A', 'D']) {
      await _choose(tester, key);
      await _tapButton(tester, key == 'D' ? 'Submit' : 'Next');
    }

    expect(
      find.text(
        'Could not submit your answers. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Question 3 of 3'), findsOneWidget);
    expect(
      find.descendant(
        of: _option('D'),
        matching: find.byIcon(Icons.radio_button_checked_rounded),
      ),
      findsOneWidget,
    );

    await _tapButton(tester, 'Submit');
    expect(find.text('Quiz completed'), findsOneWidget);
    expect(repo.submits, hasLength(2));
  });

  testWidgets('a 400 rejection shows a user-facing message, not the raw one', (
    tester,
  ) async {
    final repo = FakePersonalityRepository()
      ..submitError = ApiException(
        400,
        '"Z" is not a valid option for question "q3".',
      );
    await _pump(tester, repo);
    await _start(tester);
    for (final key in ['A', 'B', 'C']) {
      await _choose(tester, key);
      await _tapButton(tester, key == 'C' ? 'Submit' : 'Next');
    }

    expect(
      find.text(
        'The quiz has been updated. Please review your answers and submit again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('not a valid option'), findsNothing);
  });

  testWidgets('no active quiz (404) shows the unavailable state', (
    tester,
  ) async {
    await _pump(
      tester,
      FakePersonalityRepository(activeError: ApiException(404, 'none')),
    );
    await _start(tester);
    expect(find.text('No quiz is available right now.'), findsOneWidget);
  });

  testWidgets('a quiz load failure offers Retry', (tester) async {
    final repo = FakePersonalityRepository(activeError: Exception('offline'));
    await _pump(tester, repo);
    await _start(tester);
    expect(
      find.text(
        'Could not load the quiz. Check your connection and try again.',
      ),
      findsOneWidget,
    );

    repo.activeError = null;
    await _tapButton(tester, 'Retry');
    expect(find.text('Question 1 of 3'), findsOneWidget);
  });

  testWidgets('a completed user opens at the completed state and can retake '
      'with answers pre-filled', (tester) async {
    final repo = FakePersonalityRepository(
      myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
    );
    await _pump(tester, repo);

    expect(find.text('Quiz completed'), findsOneWidget);
    expect(find.text('Updated Sep 23, 2026'), findsOneWidget);
    expect(find.text('Q1 option B'), findsOneWidget);
    expect(find.text('Start Quiz'), findsNothing);

    await _tapButton(tester, 'Retake Quiz');
    expect(find.text('Question 1 of 3'), findsOneWidget);
    expect(
      find.descendant(
        of: _option('B'),
        matching: find.byIcon(Icons.radio_button_checked_rounded),
      ),
      findsOneWidget,
    );

    await _choose(tester, 'D');
    await _tapButton(tester, 'Next');
    await _tapButton(tester, 'Next');
    await _tapButton(tester, 'Submit');

    expect(repo.submits.single.quizId, 'test-quiz-v7');
    expect(repo.submits.single.answers, {'q1': 'D', 'q2': 'C', 'q3': 'A'});
    expect(find.text('Quiz completed'), findsOneWidget);
  });

  testWidgets('Done pops back to the caller', (tester) async {
    await _pump(
      tester,
      FakePersonalityRepository(
        myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
      ),
    );
    await _tapButton(tester, 'Done');
    expect(find.text('home'), findsOneWidget);
  });

  group('checking saved answers (GET /me)', () {
    testWidgets('a failed check shows Retry — not the intro', (tester) async {
      final repo = FakePersonalityRepository(meError: Exception('offline'));
      await _pump(tester, repo);

      expect(
        find.text(
          "We couldn't check your saved answers. "
          'Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Start Quiz'), findsNothing);

      repo
        ..meError = null
        ..myResponse = PsychologyQuizResponse.fromJson(myResponseJson());
      await _tapButton(tester, 'Retry');
      expect(find.text('Quiz completed'), findsOneWidget);
    });

    testWidgets('a 401 check failure also offers Retry', (tester) async {
      await _pump(
        tester,
        FakePersonalityRepository(meError: ApiException(401, 'Unauthorized')),
      );
      expect(
        find.byKey(const ValueKey('psychology-check-error')),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Start Quiz'), findsNothing);
      expect(find.text('Unauthorized'), findsNothing);
    });

    testWidgets('404 (not taken) goes straight to the intro', (tester) async {
      await _pump(
        tester,
        FakePersonalityRepository(meError: ApiException(404, 'not taken')),
      );
      expect(find.text('Start Quiz'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('psychology-check-error')),
        findsNothing,
      );
    });
  });

  group('retake cooldown', () {
    const serverMessage = 'SERVER: You can change your quiz answers again.';
    ApiException cooldown(int seconds) =>
        ApiException(429, serverMessage, retryAfterSeconds: seconds);

    NmOutlinedButton retakeButton(WidgetTester tester) =>
        tester.widget<NmOutlinedButton>(
          find.byKey(const ValueKey('psychology-retake')),
        );

    Future<void> answerAllAndSubmit(WidgetTester tester) async {
      await _choose(tester, 'D');
      await _tapButton(tester, 'Next');
      await _tapButton(tester, 'Next');
      await _tapButton(tester, 'Submit');
    }

    testWidgets('inside the hint window Retake is disabled and shows the date, '
        'with a Try anyway path', (tester) async {
      await _pump(
        tester,
        FakePersonalityRepository(
          myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
        ),
        now: _insideHint,
      );

      expect(
        find.text('You can retake the quiz from Sep 27, 2026.'),
        findsOneWidget,
      );
      expect(retakeButton(tester).onPressed, isNull);
      // The disabled button really does nothing.
      await _tapButton(tester, 'Retake Quiz');
      expect(find.text('Quiz completed'), findsOneWidget);

      await _tapButton(tester, 'Try anyway');
      expect(find.text('Question 1 of 3'), findsOneWidget);
    });

    testWidgets('after the hint window Retake is enabled with no wait text', (
      tester,
    ) async {
      await _pump(
        tester,
        FakePersonalityRepository(
          myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
        ),
      );
      expect(retakeButton(tester).onPressed, isNotNull);
      expect(
        find.byKey(const ValueKey('psychology-retake-wait')),
        findsNothing,
      );
      expect(find.text('Try anyway'), findsNothing);
    });

    testWidgets('a server 429 overrides an enabled hint: localized message, no '
        'Retry, Retake disabled, saved answers shown', (tester) async {
      final repo = FakePersonalityRepository(
        myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
      );
      await _pump(tester, repo);
      expect(retakeButton(tester).onPressed, isNotNull);

      await _tapButton(tester, 'Retake Quiz');
      repo.submitError = cooldown(3 * 86400);
      await answerAllAndSubmit(tester);

      expect(repo.submits, hasLength(1));
      expect(
        find.text('You can change your answers again in 3 days.'),
        findsOneWidget,
      );
      expect(find.text(serverMessage), findsNothing);
      expect(find.textContaining('connection'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Try anyway'), findsNothing);
      expect(find.text('Quiz completed'), findsOneWidget);
      expect(find.text('Q1 option B'), findsOneWidget); // still the saved one
      expect(retakeButton(tester).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cooldown with no saved response stays on the quiz with the '
        'answers kept and Submit disabled until an answer changes', (
      tester,
    ) async {
      final repo = FakePersonalityRepository()..submitError = cooldown(7200);
      await _pump(tester, repo);
      await _start(tester);
      await _choose(tester, 'A');
      await _tapButton(tester, 'Next');
      await _choose(tester, 'B');
      await _tapButton(tester, 'Next');
      await _choose(tester, 'C');
      await _tapButton(tester, 'Submit');

      expect(
        find.text('You can change your answers again in 2 hours.'),
        findsOneWidget,
      );
      expect(find.text('Question 3 of 3'), findsOneWidget);
      expect(
        find.descendant(
          of: _option('C'),
          matching: find.byIcon(Icons.radio_button_checked_rounded),
        ),
        findsOneWidget,
      );
      await _tapButton(tester, 'Submit');
      expect(repo.submits, hasLength(1)); // no resubmit, no auto-retry
    });

    testWidgets('a 429 without retryAfterSeconds is the generic rate limit', (
      tester,
    ) async {
      final repo = FakePersonalityRepository(
        myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
      );
      await _pump(tester, repo);
      await _tapButton(tester, 'Retake Quiz');
      repo.submitError = ApiException(429, 'ThrottlerException');
      await answerAllAndSubmit(tester);

      expect(
        find.text('Too many requests. Please wait and try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('change your answers again'), findsNothing);
      expect(find.text('Question 3 of 3'), findsOneWidget);
    });

    testWidgets('the cooldown message is localized in Tamil and fits 320dp', (
      tester,
    ) async {
      final repo = FakePersonalityRepository(
        myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
      );
      await _pump(
        tester,
        repo,
        size: const Size(320, 568),
        locale: const Locale('ta'),
      );
      await _tapButton(tester, 'தேர்வை மீண்டும் எடுக்க');
      repo.submitError = cooldown(5 * 86400);
      await _choose(tester, 'D');
      await _tapButton(tester, 'அடுத்து');
      await _tapButton(tester, 'அடுத்து');
      await _tapButton(tester, 'சமர்ப்பிக்கவும்');

      expect(
        find.text('5 நாட்களில் உங்கள் பதில்களை மீண்டும் மாற்றலாம்.'),
        findsOneWidget,
      );
      expect(find.text(serverMessage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('psychologyRetakeCooldownMessage', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final ta = lookupAppLocalizations(const Locale('ta'));
    String msg(int seconds) => psychologyRetakeCooldownMessage(en, seconds);

    test('under a day: whole hours, rounded up, never zero', () {
      expect(msg(0), 'You can change your answers again in 1 hour.');
      expect(msg(1), 'You can change your answers again in 1 hour.');
      expect(msg(3600), 'You can change your answers again in 1 hour.');
      expect(msg(3601), 'You can change your answers again in 2 hours.');
      expect(msg(86399), 'You can change your answers again in 24 hours.');
    });

    test('a day or more: whole days, rounded up', () {
      expect(msg(86400), 'You can change your answers again in 1 day.');
      expect(msg(86401), 'You can change your answers again in 2 days.');
      expect(msg(604800), 'You can change your answers again in 7 days.');
    });

    test('large values stay in days', () {
      expect(
        msg(365 * 86400),
        'You can change your answers again in 365 days.',
      );
      expect(msg(1 << 40), contains('days'));
    });

    test('Tamil', () {
      expect(
        psychologyRetakeCooldownMessage(ta, 86400),
        '1 நாளில் உங்கள் பதில்களை மீண்டும் மாற்றலாம்.',
      );
      expect(
        psychologyRetakeCooldownMessage(ta, 3 * 3600),
        '3 மணி நேரத்தில் உங்கள் பதில்களை மீண்டும் மாற்றலாம்.',
      );
    });
  });
}
