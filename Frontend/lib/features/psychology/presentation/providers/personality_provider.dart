import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_providers.dart';
import '../../data/repositories/api_personality_repository.dart';
import '../../domain/models/quiz_question.dart';
import '../../domain/models/personality_result.dart';
import '../../domain/repositories/personality_repository.dart';

/// Real backend implementation. Tests override this provider with a fake.
final personalityRepositoryProvider = Provider<PersonalityRepository>(
  (ref) => ApiPersonalityRepository(ref.watch(apiClientProvider)),
);

/// The signed-in user's saved answers to the current quiz, or null when
/// they haven't completed it. Used by ProfilePage and
/// profile_review_page.dart's summary.
final myPersonalityResultProvider =
    FutureProvider.autoDispose<PsychologyQuizResponse?>((ref) {
      return ref.watch(personalityRepositoryProvider).getMyResponse();
    });

/// [checking] is the brief `GET /me` lookup on open, which decides whether
/// the page starts at the intro or at the completed state.
enum QuizPhase { checking, intro, question, result }

/// What went wrong, kept as a kind (not a string) so the page can localize
/// it.
enum QuizError {
  /// No active quiz is configured (404).
  unavailable,

  /// The quiz could not be loaded (network or server).
  loadFailed,

  /// Submit was attempted with at least one unanswered question.
  incomplete,

  /// The backend rejected the answers (400) — e.g. the quiz changed since it
  /// was loaded. The quiz is re-fetched so the user can review and resubmit.
  rejected,

  /// The submission itself failed (network or server).
  submitFailed,
}

class PersonalityQuizState {
  final QuizPhase phase;
  final Quiz? quiz;
  final int currentIndex;
  final Map<String, String> answers; // questionId -> selected option key
  final PsychologyQuizResponse? result;
  final bool isLoading;
  final bool isSubmitting;
  final QuizError? error;

  const PersonalityQuizState({
    this.phase = QuizPhase.checking,
    this.quiz,
    this.currentIndex = 0,
    this.answers = const {},
    this.result,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
  });

  bool get isLastQuestion =>
      quiz != null && currentIndex == quiz!.questions.length - 1;

  bool get allAnswered =>
      quiz != null &&
      quiz!.questions.isNotEmpty &&
      quiz!.questions.every((q) => answers.containsKey(q.id));

  PersonalityQuizState copyWith({
    QuizPhase? phase,
    Quiz? quiz,
    int? currentIndex,
    Map<String, String>? answers,
    PsychologyQuizResponse? result,
    bool? isLoading,
    bool? isSubmitting,
    QuizError? error,
  }) {
    return PersonalityQuizState(
      phase: phase ?? this.phase,
      quiz: quiz ?? this.quiz,
      currentIndex: currentIndex ?? this.currentIndex,
      answers: answers ?? this.answers,
      result: result ?? this.result,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
    );
  }
}

/// Drives the psychology quiz sub-flow: intro card -> one question per
/// screen -> completed state (the user's saved answers). A user who has
/// already completed the current quiz opens straight at the completed state,
/// from which they can retake. Entirely independent of registration state.
final personalityQuizProvider =
    NotifierProvider.autoDispose<PersonalityQuizNotifier, PersonalityQuizState>(
      PersonalityQuizNotifier.new,
    );

class PersonalityQuizNotifier
    extends AutoDisposeNotifier<PersonalityQuizState> {
  bool _disposed = false;

  PersonalityRepository get _repository =>
      ref.read(personalityRepositoryProvider);

  @override
  PersonalityQuizState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    Future.microtask(_checkExisting);
    return const PersonalityQuizState();
  }

  void _set(PersonalityQuizState next) {
    if (!_disposed) state = next;
  }

  Future<void> _checkExisting() async {
    PsychologyQuizResponse? existing;
    try {
      existing = await _repository.getMyResponse();
    } catch (_) {
      // Not knowing whether the user has taken the quiz shouldn't block
      // them from taking it — fall through to the intro.
    }
    if (_disposed || state.phase != QuizPhase.checking) return;
    _set(
      existing != null
          ? state.copyWith(phase: QuizPhase.result, result: existing)
          : state.copyWith(phase: QuizPhase.intro),
    );
  }

  /// Loads the active quiz and moves to the first question. Also serves as
  /// "retake" and as the retry after a load error: any saved answers that
  /// still fit the (possibly newer) active quiz are pre-filled.
  Future<void> startQuiz() async {
    _set(
      state.copyWith(
        phase: QuizPhase.question,
        isLoading: true,
        currentIndex: 0,
      ),
    );
    try {
      final quiz = await _repository.getActiveQuiz();
      final saved = state.result;
      final prefill = saved != null && saved.quizId == quiz.id
          ? _validAnswers(quiz, saved.selectedKeys)
          : _validAnswers(quiz, state.answers);
      _set(state.copyWith(quiz: quiz, answers: prefill, isLoading: false));
    } on ApiException catch (e) {
      _set(
        state.copyWith(
          isLoading: false,
          error: e.statusCode == 404
              ? QuizError.unavailable
              : QuizError.loadFailed,
        ),
      );
    } catch (_) {
      _set(state.copyWith(isLoading: false, error: QuizError.loadFailed));
    }
  }

  Future<void> retake() => startQuiz();

  void answer(String questionId, String selectedKey) {
    _set(state.copyWith(answers: {...state.answers, questionId: selectedKey}));
  }

  void nextQuestion() {
    if (state.quiz == null) return;
    if (state.currentIndex < state.quiz!.questions.length - 1) {
      _set(state.copyWith(currentIndex: state.currentIndex + 1));
    }
  }

  void previousQuestion() {
    if (state.currentIndex > 0) {
      _set(state.copyWith(currentIndex: state.currentIndex - 1));
    }
  }

  Future<void> submit() async {
    final quiz = state.quiz;
    if (quiz == null || state.isSubmitting) return;

    if (!state.allAnswered) {
      final firstMissing = quiz.questions.indexWhere(
        (q) => !state.answers.containsKey(q.id),
      );
      _set(
        state.copyWith(
          currentIndex: firstMissing < 0 ? state.currentIndex : firstMissing,
          error: QuizError.incomplete,
        ),
      );
      return;
    }

    _set(state.copyWith(isSubmitting: true));
    try {
      final result = await _repository.submitAnswers(
        quizId: quiz.id,
        // In question order, and only this quiz's questions.
        answers: {for (final q in quiz.questions) q.id: state.answers[q.id]!},
      );
      _set(
        state.copyWith(
          isSubmitting: false,
          result: result,
          phase: QuizPhase.result,
        ),
      );
      if (!_disposed) ref.invalidate(myPersonalityResultProvider);
    } on ApiException catch (e) {
      if (e.statusCode == 400) {
        await _reloadAfterRejection();
      } else {
        _set(
          state.copyWith(
            isSubmitting: false,
            error: e.statusCode == 404
                ? QuizError.unavailable
                : QuizError.submitFailed,
          ),
        );
      }
    } catch (_) {
      _set(state.copyWith(isSubmitting: false, error: QuizError.submitFailed));
    }
  }

  /// A 400 means the answers no longer fit the active quiz (it was replaced,
  /// or a question/option changed). Re-fetch it, keep every answer that
  /// still fits, and point the user at the first gap — nothing is lost that
  /// can still be submitted.
  Future<void> _reloadAfterRejection() async {
    try {
      final quiz = await _repository.getActiveQuiz();
      if (quiz.questions.isEmpty) {
        _set(state.copyWith(isSubmitting: false, error: QuizError.unavailable));
        return;
      }
      final kept = _validAnswers(quiz, state.answers);
      final firstMissing = quiz.questions.indexWhere(
        (q) => !kept.containsKey(q.id),
      );
      _set(
        state.copyWith(
          quiz: quiz,
          answers: kept,
          currentIndex: firstMissing < 0
              ? state.currentIndex.clamp(0, quiz.questions.length - 1)
              : firstMissing,
          isSubmitting: false,
          error: QuizError.rejected,
        ),
      );
    } catch (_) {
      _set(state.copyWith(isSubmitting: false, error: QuizError.rejected));
    }
  }

  static Map<String, String> _validAnswers(
    Quiz quiz,
    Map<String, String> answers,
  ) {
    return {
      for (final entry in answers.entries)
        if (quiz.questionById(entry.key)?.hasOption(entry.value) ?? false)
          entry.key: entry.value,
    };
  }
}
