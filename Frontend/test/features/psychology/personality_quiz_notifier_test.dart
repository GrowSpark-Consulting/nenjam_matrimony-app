import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/personality_result.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/quiz_question.dart';
import 'package:nenjam_matrimony/features/psychology/presentation/providers/personality_provider.dart';

import 'psychology_test_support.dart';

/// Builds a container around [repo], keeps the autoDispose notifier alive,
/// and lets its on-open `GET /me` check settle.
Future<ProviderContainer> _container(FakePersonalityRepository repo) async {
  final container = ProviderContainer(
    overrides: [personalityRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  container.listen(personalityQuizProvider, (_, __) {});
  await Future<void>.delayed(Duration.zero);
  return container;
}

PersonalityQuizState _state(ProviderContainer c) =>
    c.read(personalityQuizProvider);

PersonalityQuizNotifier _notifier(ProviderContainer c) =>
    c.read(personalityQuizProvider.notifier);

void main() {
  group('opening the quiz', () {
    test('not taken (GET /me -> null) starts at the intro', () async {
      final c = await _container(FakePersonalityRepository());
      expect(_state(c).phase, QuizPhase.intro);
    });

    test(
      'already taken opens at the completed state with the answers',
      () async {
        final c = await _container(
          FakePersonalityRepository(
            myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
          ),
        );
        expect(_state(c).phase, QuizPhase.result);
        expect(_state(c).result!.answers, hasLength(3));
      },
    );

    test('a failed GET /me does not block the quiz — intro', () async {
      final c = await _container(
        FakePersonalityRepository(meError: Exception('offline')),
      );
      expect(_state(c).phase, QuizPhase.intro);
    });
  });

  group('loading', () {
    test('startQuiz loads the active quiz with a dynamic length', () async {
      final repo = FakePersonalityRepository(
        quiz: Quiz.fromJson(activeQuizJson(questionCount: 5)),
      );
      final c = await _container(repo);
      await _notifier(c).startQuiz();

      expect(_state(c).phase, QuizPhase.question);
      expect(_state(c).quiz!.questions, hasLength(5));
      expect(_state(c).currentIndex, 0);
      expect(_state(c).answers, isEmpty);
      expect(_state(c).error, isNull);
    });

    test('404 on /active -> unavailable', () async {
      final c = await _container(
        FakePersonalityRepository(
          activeError: ApiException(404, 'No active psychology quiz'),
        ),
      );
      await _notifier(c).startQuiz();
      expect(_state(c).quiz, isNull);
      expect(_state(c).error, QuizError.unavailable);
    });

    test(
      'network failure on /active -> loadFailed, and retry recovers',
      () async {
        final repo = FakePersonalityRepository(activeError: Exception('down'));
        final c = await _container(repo);
        await _notifier(c).startQuiz();
        expect(_state(c).error, QuizError.loadFailed);

        repo.activeError = null;
        await _notifier(c).startQuiz();
        expect(_state(c).error, isNull);
        expect(_state(c).quiz, isNotNull);
      },
    );
  });

  group('answering and navigation', () {
    test('stores the selected option KEY per question id', () async {
      final c = await _container(FakePersonalityRepository());
      await _notifier(c).startQuiz();
      _notifier(c).answer('q1', 'C');
      _notifier(c).answer('q1', 'D'); // changing an answer replaces it
      _notifier(c).answer('q2', 'A');
      expect(_state(c).answers, {'q1': 'D', 'q2': 'A'});
    });

    test('next/previous are bounded by questions.length', () async {
      final c = await _container(FakePersonalityRepository());
      await _notifier(c).startQuiz();
      final n = _notifier(c);

      n.previousQuestion();
      expect(_state(c).currentIndex, 0);
      n.nextQuestion();
      n.nextQuestion();
      expect(_state(c).currentIndex, 2);
      expect(_state(c).isLastQuestion, isTrue);
      n.nextQuestion();
      expect(_state(c).currentIndex, 2);
      n.previousQuestion();
      expect(_state(c).currentIndex, 1);
    });
  });

  group('submit', () {
    test('incomplete answers are not sent; jumps to the first gap', () async {
      final repo = FakePersonalityRepository();
      final c = await _container(repo);
      await _notifier(c).startQuiz();
      _notifier(c).answer('q1', 'A');
      _notifier(c).answer('q3', 'B');
      _notifier(c).nextQuestion();
      _notifier(c).nextQuestion();

      await _notifier(c).submit();

      expect(repo.submits, isEmpty);
      expect(_state(c).error, QuizError.incomplete);
      expect(_state(c).currentIndex, 1);
      expect(_state(c).phase, QuizPhase.question);
    });

    test('submits the loaded quizId and every answer in question order, '
        'then shows the completed state', () async {
      final repo = FakePersonalityRepository(
        quiz: Quiz.fromJson(activeQuizJson(id: 'server-given-id')),
      );
      final c = await _container(repo);
      await _notifier(c).startQuiz();
      _notifier(c).answer('q3', 'D');
      _notifier(c).answer('q1', 'B');
      _notifier(c).answer('q2', 'C');

      await _notifier(c).submit();

      expect(repo.submits.single.quizId, 'server-given-id');
      expect(repo.submits.single.answers.keys, ['q1', 'q2', 'q3']);
      expect(repo.submits.single.answers, {'q1': 'B', 'q2': 'C', 'q3': 'D'});
      expect(_state(c).phase, QuizPhase.result);
      expect(_state(c).isSubmitting, isFalse);
      expect(_state(c).result!.selectedKeys, {'q1': 'B', 'q2': 'C', 'q3': 'D'});
    });

    test('a network failure stops loading, keeps answers, stays on the quiz, '
        'and can be retried', () async {
      final repo = FakePersonalityRepository()
        ..submitError = Exception('timeout');
      final c = await _container(repo);
      await _notifier(c).startQuiz();
      for (final q in ['q1', 'q2', 'q3']) {
        _notifier(c).answer(q, 'A');
      }

      await _notifier(c).submit();
      expect(_state(c).isSubmitting, isFalse);
      expect(_state(c).error, QuizError.submitFailed);
      expect(_state(c).phase, QuizPhase.question);
      expect(_state(c).answers, {'q1': 'A', 'q2': 'A', 'q3': 'A'});

      await _notifier(c).submit(); // retry
      expect(_state(c).phase, QuizPhase.result);
      expect(repo.submits, hasLength(2));
    });

    test('a 400 (quiz changed) re-fetches the quiz, keeps answers that still '
        'fit, and points at the first gap', () async {
      final repo = FakePersonalityRepository();
      final c = await _container(repo);
      await _notifier(c).startQuiz();
      for (final q in ['q1', 'q2', 'q3']) {
        _notifier(c).answer(q, 'B');
      }
      // The active quiz is replaced by one with an extra question.
      repo
        ..submitError = ApiException(400, 'quizId does not match')
        ..quiz = Quiz.fromJson(activeQuizJson(id: 'new-id', questionCount: 4));

      await _notifier(c).submit();

      expect(_state(c).error, QuizError.rejected);
      expect(_state(c).isSubmitting, isFalse);
      expect(_state(c).phase, QuizPhase.question);
      expect(_state(c).quiz!.id, 'new-id');
      expect(_state(c).answers, {'q1': 'B', 'q2': 'B', 'q3': 'B'});
      expect(_state(c).currentIndex, 3);

      _notifier(c).answer('q4', 'A');
      await _notifier(c).submit();
      expect(repo.submits.last.quizId, 'new-id');
      expect(_state(c).phase, QuizPhase.result);
    });
  });

  group('retake', () {
    test(
      'pre-fills saved answers and resubmits through the same endpoint',
      () async {
        final repo = FakePersonalityRepository(
          myResponse: PsychologyQuizResponse.fromJson(myResponseJson()),
        );
        final c = await _container(repo);
        expect(_state(c).phase, QuizPhase.result);

        await _notifier(c).retake();
        expect(_state(c).phase, QuizPhase.question);
        expect(_state(c).currentIndex, 0);
        expect(_state(c).answers, {'q1': 'B', 'q2': 'C', 'q3': 'A'});

        _notifier(c).answer('q2', 'D');
        await _notifier(c).submit();
        expect(repo.submits.single.answers, {'q1': 'B', 'q2': 'D', 'q3': 'A'});
        expect(_state(c).phase, QuizPhase.result);
        expect(_state(c).result!.selectedKeys['q2'], 'D');
      },
    );

    test(
      'saved answers from a different (retired) quiz are not pre-filled',
      () async {
        final repo = FakePersonalityRepository(
          myResponse: PsychologyQuizResponse.fromJson(
            myResponseJson(quizId: 'retired-quiz'),
          ),
        );
        final c = await _container(repo);
        await _notifier(c).retake();
        expect(_state(c).answers, isEmpty);
      },
    );
  });
}
