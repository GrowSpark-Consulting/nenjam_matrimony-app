import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/personality_result.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/quiz_question.dart';
import 'package:nenjam_matrimony/features/psychology/presentation/pages/psychology_quiz_page.dart';
import 'package:nenjam_matrimony/features/psychology/presentation/providers/personality_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'psychology_test_support.dart';

Future<void> _pump(
  WidgetTester tester,
  FakePersonalityRepository repo, {
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
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
      overrides: [personalityRepositoryProvider.overrideWithValue(repo)],
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
}
