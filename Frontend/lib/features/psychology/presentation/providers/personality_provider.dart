import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_providers.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../../../matches/presentation/providers/reel_feed_provider.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../../data/repositories/api_personality_repository.dart';
import '../../domain/models/quiz_question.dart';
import '../../domain/models/personality_result.dart';
import '../../domain/repositories/personality_repository.dart';

/// Real backend implementation. Tests override this provider with a fake.
final personalityRepositoryProvider = Provider<PersonalityRepository>(
  (ref) => ApiPersonalityRepository(ref.watch(apiClientProvider)),
);

/// "Now" for the retake-cooldown hint and a server cooldown's end date.
/// Tests override it so date-dependent states are deterministic.
final psychologyClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The signed-in user's saved answers to the current quiz, or null when
/// they have no current response (`GET /me` 404). Any other failure is an
/// [AsyncError] — never "not taken". Used by ProfilePage and
/// profile_review_page.dart's summary.
final myPersonalityResultProvider =
    FutureProvider.autoDispose<PsychologyQuizResponse?>((ref) {
      return ref.watch(personalityRepositoryProvider).getMyResponse();
    });

/// [checking] is the brief `GET /me` lookup on open, which decides whether
/// the page starts at the intro or at the completed state. If that lookup
/// fails the page stays in [checking] with [QuizError.checkFailed].
enum QuizPhase { checking, intro, question, result }

/// What went wrong, kept as a kind (not a string) so the page can localize
/// it.
enum QuizError {
  /// `GET /me` failed for a reason other than 404 (network, 401, 5xx), so
  /// it's unknown whether the user already has saved answers. Retryable;
  /// never treated as "not taken".
  checkFailed,

  /// No active quiz is configured (404).
  unavailable,

  /// The quiz could not be loaded (network or server).
  loadFailed,

  /// Submit was attempted with at least one unanswered question.
  incomplete,

  /// The backend rejected the answers (400) — e.g. the quiz changed since it
  /// was loaded. The quiz is re-fetched so the user can review and resubmit.
  rejected,

  /// The retake cooldown is active (429 with `retryAfterSeconds`, carried in
  /// [PersonalityQuizState.cooldownSeconds]). Not retryable until it ends.
  retakeCooldown,

  /// The general per-IP rate limit (429 without `retryAfterSeconds`).
  rateLimited,

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

  /// The server's `retryAfterSeconds` for [QuizError.retakeCooldown]; like
  /// [error], cleared by any [copyWith] that doesn't pass it again.
  final int? cooldownSeconds;

  /// When a submit's 429 said the answers can next be changed. It's the
  /// server's own figure, so it overrides the client-side hint from
  /// [PsychologyQuizResponse.retakeHintAvailableAt].
  final DateTime? serverRetakeAvailableAt;

  const PersonalityQuizState({
    this.phase = QuizPhase.checking,
    this.quiz,
    this.currentIndex = 0,
    this.answers = const {},
    this.result,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.cooldownSeconds,
    this.serverRetakeAvailableAt,
  });

  bool get isLastQuestion =>
      quiz != null && currentIndex == quiz!.questions.length - 1;

  bool get allAnswered =>
      quiz != null &&
      quiz!.questions.isNotEmpty &&
      quiz!.questions.every((q) => answers.containsKey(q.id));

  /// When the saved answers can next be changed: the server's figure after
  /// a 429, otherwise the client hint (`completedAt` + the default
  /// cooldown). Null when there's nothing to wait for (or no way to tell).
  DateTime? get retakeAvailableAt =>
      serverRetakeAvailableAt ?? result?.retakeHintAvailableAt();

  PersonalityQuizState copyWith({
    QuizPhase? phase,
    Quiz? quiz,
    int? currentIndex,
    Map<String, String>? answers,
    PsychologyQuizResponse? result,
    bool? isLoading,
    bool? isSubmitting,
    QuizError? error,
    int? cooldownSeconds,
    DateTime? serverRetakeAvailableAt,
    bool clearServerRetakeAvailableAt = false,
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
      cooldownSeconds: cooldownSeconds,
      serverRetakeAvailableAt: clearServerRetakeAvailableAt
          ? null
          : serverRetakeAvailableAt ?? this.serverRetakeAvailableAt,
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
  /// Upper bound for turning a server `retryAfterSeconds` into a date, so an
  /// absurd value can't overflow [DateTime] arithmetic.
  static const _maxCooldown = Duration(days: 3650);

  bool _disposed = false;

  PersonalityRepository get _repository =>
      ref.read(personalityRepositoryProvider);

  DateTime _now() => ref.read(psychologyClockProvider)();

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
    } on ApiException catch (e) {
      // 404 is the normal "no current response" — the intro.
      if (e.statusCode != 404) {
        _onCheckFailed();
        return;
      }
    } catch (_) {
      _onCheckFailed();
      return;
    }
    if (_disposed || state.phase != QuizPhase.checking) return;
    _set(
      existing != null
          ? state.copyWith(phase: QuizPhase.result, result: existing)
          : state.copyWith(phase: QuizPhase.intro),
    );
  }

  /// Not knowing whether the user already has answers is not the same as
  /// "not taken": sending a completed member through every question only
  /// for the retake cooldown to reject them is worse than a retry. (A 401
  /// has already been through the auth interceptor's refresh/sign-out.)
  void _onCheckFailed() {
    if (_disposed || state.phase != QuizPhase.checking) return;
    _set(state.copyWith(error: QuizError.checkFailed));
  }

  /// Repeats the on-open `GET /me` check after [QuizError.checkFailed].
  Future<void> retryCheck() async {
    if (state.phase != QuizPhase.checking) return;
    _set(state.copyWith()); // clears the error -> spinner
    await _checkExisting();
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

  /// Starts a retake. Never gated on the cooldown hint — the page decides
  /// whether to offer it, and the server's 429 is the authority on submit.
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
          clearServerRetakeAvailableAt: true,
        ),
      );
      if (!_disposed) _invalidateAfterSubmit();
    } on ApiException catch (e) {
      if (e.statusCode == 400) {
        await _reloadAfterRejection();
      } else if (e.statusCode == 429) {
        _onTooManyRequests(e.retryAfterSeconds);
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

  /// After a successful submit: the user's own status, plus every provider
  /// that reads `GET /discover` / `GET /discover/search`, since a real
  /// change can reorder the feed. The backend also emits `feed.invalidate`
  /// (reason `psychology_updated`, handled in realtime_providers.dart), but
  /// realtime delivery is best-effort — this is the local fallback. A
  /// duplicate is just one idempotent re-fetch.
  void _invalidateAfterSubmit() {
    ref.invalidate(myPersonalityResultProvider);
    ref.invalidate(discoverFeedProvider);
    ref.invalidate(reelFeedProvider);
    ref.invalidate(searchResultsProvider);
  }

  /// A 429 *with* `retryAfterSeconds` is the retake cooldown; without it,
  /// it's the global per-IP rate limit and says nothing about retakes.
  /// Either way nothing is retried automatically and every answer is kept.
  void _onTooManyRequests(int? retryAfterSeconds) {
    if (retryAfterSeconds == null) {
      _set(state.copyWith(isSubmitting: false, error: QuizError.rateLimited));
      return;
    }
    final wait = Duration(
      seconds: math.min(retryAfterSeconds, _maxCooldown.inSeconds),
    );
    _set(
      state.copyWith(
        isSubmitting: false,
        error: QuizError.retakeCooldown,
        cooldownSeconds: retryAfterSeconds,
        serverRetakeAvailableAt: _now().add(wait),
        // Back to the saved answers, which are still in force; the attempted
        // ones stay in [PersonalityQuizState.answers].
        phase: state.result != null ? QuizPhase.result : null,
      ),
    );
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
