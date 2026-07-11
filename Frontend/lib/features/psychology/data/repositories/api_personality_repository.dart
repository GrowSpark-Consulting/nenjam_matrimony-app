import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/models/quiz_question.dart';
import '../../domain/models/personality_result.dart';
import '../../domain/repositories/personality_repository.dart';

/// Real backend implementation — not wired by default (see
/// `personalityRepositoryProvider`). Ready for the backend team to connect
/// by flipping that provider's override once their endpoints are live.
class ApiPersonalityRepository implements PersonalityRepository {
  ApiPersonalityRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<Quiz> getQuizQuestions() async {
    final response = await _apiClient
        .get<Map<String, dynamic>>(ApiEndpoints.psychologyQuizActive);
    return Quiz.fromJson(response.data ?? {});
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
    return _toResult(response.data ?? {});
  }

  @override
  Future<PersonalityResult?> getMyResult() async {
    final response = await _apiClient
        .get<Map<String, dynamic>>(ApiEndpoints.psychologyQuizMe);
    final data = response.data;
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
