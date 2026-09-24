import 'dart:async';

import 'package:nenjam_matrimony/features/psychology/domain/models/personality_result.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/quiz_question.dart';
import 'package:nenjam_matrimony/features/psychology/domain/repositories/personality_repository.dart';

/// Shared fixtures for the psychology quiz tests — shaped exactly like the
/// backend's `GET /psychology/quiz/active` / `GET /psychology/quiz/me`
/// responses (`backend/apps/api/src/modules/psychology`). Deliberately a
/// different quiz id and question count from the seeded quiz, so nothing
/// here can pass by accident against a hardcoded id or length.

Map<String, dynamic> option(String key, String label, int value) => {
  'key': key,
  'label': label,
  'value': value,
};

Map<String, dynamic> activeQuizJson({
  String id = 'test-quiz-v7',
  int questionCount = 3,
}) => {
  'id': id,
  'title': 'Marriage Compatibility Quiz',
  'description': 'Scenario-based questions.',
  'version': '7.0',
  // Out of order on purpose — the client sorts by `order`.
  'questions': [
    for (var i = questionCount; i >= 1; i--)
      {
        'id': 'q$i',
        'order': i,
        'dimension': 'dimension_$i',
        'questionText': 'Question $i text?',
        'options': [
          option('A', 'Q$i option A', 1),
          option('B', 'Q$i option B', 2),
          option('C', 'Q$i option C', 3),
          option('D', 'Q$i option D', 4),
        ],
      },
  ],
};

/// A question whose labels are as long as the real seeded ones.
Map<String, dynamic> longLabelQuizJson() => {
  'id': 'test-quiz-long',
  'title': 'Marriage Compatibility Quiz',
  'description': null,
  'version': '1.0',
  'questions': [
    {
      'id': 'long-1',
      'order': 1,
      'dimension': 'career_adaptability',
      'questionText':
          'If one of you receives a major career opportunity in another city, '
          'how do you expect the two of you to decide what to do about it?',
      'options': [
        option(
          'A',
          'I expect my career to take priority at times, and my partner to '
              'be willing to adapt around it',
          1,
        ),
        option(
          'B',
          "We'd weigh it together each time and prioritize whichever "
              'opportunity benefits the family more',
          2,
        ),
        option(
          'C',
          "My career matters, but I'd want stability/location to take "
              'priority over big career swings',
          3,
        ),
        option(
          'D',
          'I expect to scale back my career for family life if needed',
          4,
        ),
      ],
    },
  ],
};

Map<String, dynamic> myResponseJson({
  String quizId = 'test-quiz-v7',
  Map<String, String> answers = const {'q1': 'B', 'q2': 'C', 'q3': 'A'},
  String completedAt = '2026-09-20T10:00:00.000Z',
  String updatedAt = '2026-09-23T10:00:00.000Z',
}) => {
  'quizId': quizId,
  'answers': [
    for (final e in answers.entries)
      {
        'questionId': e.key,
        'dimension': 'dimension_${e.key}',
        'questionText': 'Question ${e.key.substring(1)} text?',
        'selectedKey': e.value,
        'selectedLabel': 'Q${e.key.substring(1)} option ${e.value}',
      },
  ],
  'completedAt': completedAt,
  'updatedAt': updatedAt,
};

/// Hand-written fake (the repo uses no mocking library). Each call reads the
/// current field value, so a test can change behavior mid-flow.
class FakePersonalityRepository implements PersonalityRepository {
  FakePersonalityRepository({
    Quiz? quiz,
    this.myResponse,
    this.activeError,
    this.meError,
  }) : quiz = quiz ?? Quiz.fromJson(activeQuizJson());

  Quiz quiz;
  PsychologyQuizResponse? myResponse;
  Object? activeError;
  Object? meError;

  /// Thrown by the next submit, then cleared.
  Object? submitError;

  /// When set, submit waits on it (for loading-state tests).
  Completer<void>? submitGate;

  int activeCalls = 0;
  final List<({String quizId, Map<String, String> answers})> submits = [];

  @override
  Future<Quiz> getActiveQuiz() async {
    activeCalls++;
    if (activeError != null) throw activeError!;
    return quiz;
  }

  @override
  Future<PsychologyQuizResponse?> getMyResponse() async {
    if (meError != null) throw meError!;
    return myResponse;
  }

  @override
  Future<PsychologyQuizResponse> submitAnswers({
    required String quizId,
    required Map<String, String> answers,
  }) async {
    submits.add((quizId: quizId, answers: Map.of(answers)));
    if (submitGate != null) await submitGate!.future;
    final error = submitError;
    if (error != null) {
      submitError = null;
      throw error;
    }
    myResponse = PsychologyQuizResponse.fromJson(
      myResponseJson(quizId: quizId, answers: answers),
    );
    return myResponse!;
  }
}
