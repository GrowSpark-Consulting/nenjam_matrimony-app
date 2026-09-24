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

  /// `POST /psychology/quiz/submit` — submitting again is a retake (the
  /// backend upserts). [answers] maps questionId -> selected option key.
  Future<PsychologyQuizResponse> submitAnswers({
    required String quizId,
    required Map<String, String> answers,
  });

  /// `GET /psychology/quiz/me`. Null when the user hasn't completed the
  /// current quiz.
  Future<PsychologyQuizResponse?> getMyResponse();
}
