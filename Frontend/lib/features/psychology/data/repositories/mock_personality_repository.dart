import '../../domain/models/quiz_question.dart';
import '../../domain/models/personality_result.dart';
import '../../domain/repositories/personality_repository.dart';

class _MockQuestion {
  final String id;
  final String domain; // 'O' | 'C' | 'E' | 'A' | 'N'
  final String text;
  final bool reverseScored;

  const _MockQuestion(this.id, this.domain, this.text, this.reverseScored);
}

/// In-memory mock — no network calls. Default implementation until the
/// backend team ships real endpoints (see [ApiPersonalityRepository]).
///
/// Scoring mirrors the standard OCEAN formula: reverse-scored answers are
/// flipped (6 - score) before averaging per trait, then mapped from the
/// 1-5 Likert range to 0-100.
class MockPersonalityRepository implements PersonalityRepository {
  static const _quizId = 'mock-ocean-quiz-v1';

  static const List<_MockQuestion> _questions = [
    _MockQuestion('o1', 'O', 'I enjoy exploring new ideas and experiences.', false),
    _MockQuestion('o2', 'O', 'I prefer familiar routines over new ones.', true),
    _MockQuestion('c1', 'C', 'I keep my commitments organised and on time.', false),
    _MockQuestion('c2', 'C', 'I often leave tasks unfinished.', true),
    _MockQuestion('e1', 'E', 'I enjoy meeting new people.', false),
    _MockQuestion('e2', 'E', 'I prefer quiet evenings alone over social events.', true),
    _MockQuestion('a1', 'A', 'I genuinely care about how others feel.', false),
    _MockQuestion('a2', 'A', 'I can be blunt or critical with others.', true),
    _MockQuestion('n1', 'N', 'I often feel anxious or worried.', false),
    _MockQuestion('n2', 'N', 'I stay calm even under pressure.', true),
  ];

  PersonalityResult? _saved;

  @override
  Future<Quiz> getQuizQuestions() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return Quiz(
      id: _quizId,
      title: 'OCEAN Personality Profile',
      description:
          'A short assessment based on the Big Five personality model. '
          'Results help us find more compatible matches for you.',
      questions: _questions
          .asMap()
          .entries
          .map((e) => QuizQuestion(
                id: e.value.id,
                oceanDomain: e.value.domain,
                questionText: e.value.text,
                order: e.key + 1,
              ))
          .toList(),
    );
  }

  @override
  Future<PersonalityResult> submitPersonalityQuiz(
    Map<String, int> answers,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final byDomain = <String, List<int>>{};
    for (final q in _questions) {
      final score = answers[q.id];
      if (score == null) continue;
      final adjusted = q.reverseScored ? 6 - score : score;
      byDomain.putIfAbsent(q.domain, () => []).add(adjusted);
    }

    int scoreFor(String domain) {
      final bucket = byDomain[domain];
      if (bucket == null || bucket.isEmpty) return 0;
      final mean = bucket.reduce((a, b) => a + b) / bucket.length;
      return (((mean - 1) / 4) * 100).round().clamp(0, 100);
    }

    final result = PersonalityResult(
      completed: true,
      completedAt: DateTime.now(),
      openness: scoreFor('O'),
      conscientiousness: scoreFor('C'),
      extraversion: scoreFor('E'),
      agreeableness: scoreFor('A'),
      neuroticism: scoreFor('N'),
    );
    _saved = result;
    return result;
  }

  @override
  Future<PersonalityResult?> getMyResult() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _saved;
  }
}
