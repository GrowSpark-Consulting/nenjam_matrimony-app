import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/quiz_question.dart';
import '../../domain/models/personality_result.dart';
import '../../domain/repositories/personality_repository.dart';

/// Real backend implementation — wired as the default (see
/// `personalityRepositoryProvider`). Talks to the `psychology` module
/// (`backend/apps/api/src/modules/psychology`).
class ApiPersonalityRepository implements PersonalityRepository {
  ApiPersonalityRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<Quiz> getActiveQuiz() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.psychologyQuizActive,
    );
    return Quiz.fromJson(
      unwrapOrThrow(response.statusCode, response.data) ?? {},
    );
  }

  @override
  Future<PsychologyQuizResponse> submitAnswers({
    required String quizId,
    required Map<String, String> answers,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.psychologyQuizSubmit,
      data: {
        'quizId': quizId,
        'answers': answers.entries
            .map((e) => {'questionId': e.key, 'selectedKey': e.value})
            .toList(),
      },
    );
    return PsychologyQuizResponse.fromJson(
      unwrapOrThrow(response.statusCode, response.data) ?? {},
    );
  }

  @override
  Future<PsychologyQuizResponse?> getMyResponse() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.psychologyQuizMe,
    );
    // 404 is the backend's "not taken yet" (or "saved answers no longer fit
    // the active quiz", or "no active quiz") — either way the user has no
    // current response, which is a normal state. Every other failure throws.
    if (response.statusCode == 404) return null;
    final data = unwrapOrThrow(response.statusCode, response.data);
    if (data == null || data.isEmpty) return null;
    return PsychologyQuizResponse.fromJson(data);
  }
}
