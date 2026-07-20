import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/quiz_question.dart';
import '../../domain/models/personality_result.dart';
import '../../domain/repositories/personality_repository.dart';

/// Real backend implementation — wired as the default (see
/// `personalityRepositoryProvider`).
///
/// TODO(backend): GET /psychology/quiz/active, GET /psychology/quiz/me,
/// POST /psychology/quiz/submit — no `psychology` backend module exists
/// yet (confirmed: zero files anywhere in the backend repo mention
/// "psychology"), so every call here 404s until that module is built. Every
/// caller already handles the resulting error via AsyncValue/try-catch, so
/// this is safe to leave wired — no UI change needed once the backend
/// lands, only this repository starts succeeding.
class ApiPersonalityRepository implements PersonalityRepository {
  ApiPersonalityRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<Quiz> getQuizQuestions() async {
    final response = await _apiClient
        .get<Map<String, dynamic>>(ApiEndpoints.psychologyQuizActive);
    return Quiz.fromJson(unwrapOrThrow(response.statusCode, response.data) ?? {});
  }

  @override
  Future<PersonalityResult> submitPersonalityQuiz(
    Map<String, int> answers,
  ) async {
    final quiz = await getQuizQuestions();
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.psychologyQuizSubmit,
      data: {
        'quizId': quiz.id,
        'answers': answers.entries
            .map((e) => {'questionId': e.key, 'score': e.value})
            .toList(),
      },
    );
    return _toResult(unwrapOrThrow(response.statusCode, response.data) ?? {});
  }

  @override
  Future<PersonalityResult?> getMyResult() async {
    final response = await _apiClient
        .get<Map<String, dynamic>>(ApiEndpoints.psychologyQuizMe);
    final data = unwrapOrThrow(response.statusCode, response.data);
    if (data == null || data.isEmpty) return null;
    return _toResult(data);
  }

  PersonalityResult _toResult(Map<String, dynamic> json) {
    final score = json['oceanScore'] as Map<String, dynamic>? ?? {};
    return PersonalityResult(
      completed: true,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      openness: (score['O'] as num?)?.toInt() ?? 0,
      conscientiousness: (score['C'] as num?)?.toInt() ?? 0,
      extraversion: (score['E'] as num?)?.toInt() ?? 0,
      agreeableness: (score['A'] as num?)?.toInt() ?? 0,
      neuroticism: (score['N'] as num?)?.toInt() ?? 0,
    );
  }
}
