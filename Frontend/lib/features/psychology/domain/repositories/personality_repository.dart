import '../models/quiz_question.dart';
import '../models/personality_result.dart';

/// Relationship Intelligence — Marriage Compatibility (psychology) quiz.
///
/// Fully independent of the registration feature. Answer storage and
/// validation only: every compatibility score is computed server-side,
/// pairwise, and never reaches this interface.
abstract class PersonalityRepository {
  /// `GET /psychology/quiz/active`. Throws [ApiException] (404 when no quiz
  /// is configured).
  Future<Quiz> getActiveQuiz();

  /// `POST /psychology/quiz/submit`. [answers] maps questionId -> selected
  /// option key. The first submission is always saved. Submitting the same
  /// answers again succeeds and changes nothing (no cooldown is started).
  /// Different answers are a retake, which the backend limits to one change
  /// per cooldown (default 7 days, counted from `completedAt`) — inside it,
  /// this throws an [ApiException] with status 429 and
  /// [ApiException.retryAfterSeconds]. Stale saved answers (the quiz changed)
  /// are replaced immediately, with no cooldown.
  Future<PsychologyQuizResponse> submitAnswers({
    required String quizId,
    required Map<String, String> answers,
  });

  /// `GET /psychology/quiz/me`. Null when the user has no *current* response
  /// (404: never taken, or their saved answers no longer fit the active
  /// quiz). Any other failure throws — callers must not read an error as
  /// "not taken".
  Future<PsychologyQuizResponse?> getMyResponse();
}
