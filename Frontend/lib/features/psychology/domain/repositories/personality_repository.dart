import '../models/quiz_question.dart';
import '../models/personality_result.dart';

/// Relationship Intelligence — OCEAN Personality Quiz.
///
/// Fully independent of the registration feature. [MockPersonalityRepository]
/// is wired as the default today; swap the `personalityRepositoryProvider`
/// override to [ApiPersonalityRepository] once the backend team's endpoints
/// are ready.
abstract class PersonalityRepository {
  Future<Quiz> getQuizQuestions();

  /// [answers] maps questionId -> Likert score (1-5).
  Future<PersonalityResult> submitPersonalityQuiz(Map<String, int> answers);

  Future<PersonalityResult?> getMyResult();
}
