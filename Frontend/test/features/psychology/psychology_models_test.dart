import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/personality_result.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/quiz_question.dart';

import 'psychology_test_support.dart';

void main() {
  group('Quiz.fromJson (GET /psychology/quiz/active)', () {
    test('parses quiz metadata and keeps the backend-supplied id', () {
      final quiz = Quiz.fromJson(activeQuizJson(id: 'whatever-v9'));
      expect(quiz.id, 'whatever-v9');
      expect(quiz.title, 'Marriage Compatibility Quiz');
      expect(quiz.description, 'Scenario-based questions.');
      expect(quiz.version, '7.0');
    });

    test('parses questions sorted by order, with dimension and text', () {
      final quiz = Quiz.fromJson(activeQuizJson(questionCount: 3));
      expect(quiz.questions.map((q) => q.id), ['q1', 'q2', 'q3']);
      expect(quiz.questions.map((q) => q.order), [1, 2, 3]);
      final q1 = quiz.questions.first;
      expect(q1.dimension, 'dimension_1');
      expect(q1.questionText, 'Question 1 text?');
    });

    test('parses every option key/label/value', () {
      final options = Quiz.fromJson(activeQuizJson()).questions.first.options;
      expect(options.map((o) => o.key), ['A', 'B', 'C', 'D']);
      expect(options.map((o) => o.label), [
        'Q1 option A',
        'Q1 option B',
        'Q1 option C',
        'Q1 option D',
      ]);
      expect(options.map((o) => o.value), [1, 2, 3, 4]);
    });

    test('a null description and missing options are tolerated', () {
      final quiz = Quiz.fromJson({
        'id': 'x',
        'title': 't',
        'description': null,
        'version': '1.0',
        'questions': [
          {'id': 'q', 'order': 1, 'dimension': 'd', 'questionText': '?'},
        ],
      });
      expect(quiz.description, isNull);
      expect(quiz.questions.single.options, isEmpty);
    });

    test('hasOption / questionById', () {
      final quiz = Quiz.fromJson(activeQuizJson());
      expect(quiz.questionById('q2')!.hasOption('D'), isTrue);
      expect(quiz.questionById('q2')!.hasOption('E'), isFalse);
      expect(quiz.questionById('nope'), isNull);
    });
  });

  group('QuizOption.fromJson', () {
    test('reads key, label and numeric value', () {
      final o = QuizOption.fromJson(option('C', 'Middle ground', 3));
      expect(o.key, 'C');
      expect(o.label, 'Middle ground');
      expect(o.value, 3);
    });
  });

  group('PsychologyQuizResponse.fromJson (GET /psychology/quiz/me)', () {
    test('parses answers, labels and both timestamps', () {
      final r = PsychologyQuizResponse.fromJson(myResponseJson());
      expect(r.quizId, 'test-quiz-v7');
      expect(r.answers, hasLength(3));
      final first = r.answers.first;
      expect(first.questionId, 'q1');
      expect(first.dimension, 'dimension_q1');
      expect(first.questionText, 'Question 1 text?');
      expect(first.selectedKey, 'B');
      expect(first.selectedLabel, 'Q1 option B');
      expect(r.completedAt, DateTime.utc(2026, 9, 20, 10));
      expect(r.updatedAt, DateTime.utc(2026, 9, 23, 10));
    });

    test('"last taken" reads updatedAt, not completedAt', () {
      final r = PsychologyQuizResponse.fromJson(myResponseJson());
      expect(r.lastUpdatedAt, DateTime.utc(2026, 9, 23, 10));
    });

    test('selectedKeys maps questionId -> selectedKey', () {
      final r = PsychologyQuizResponse.fromJson(myResponseJson());
      expect(r.selectedKeys, {'q1': 'B', 'q2': 'C', 'q3': 'A'});
    });
  });
}
