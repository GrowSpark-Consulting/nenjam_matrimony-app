import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/quiz_question.dart';
import '../../domain/models/personality_result.dart';
import '../../domain/repositories/personality_repository.dart';
import '../../data/repositories/mock_personality_repository.dart';

/// Default implementation is the in-memory mock. Override this provider
/// with an `ApiPersonalityRepository` once the backend team's endpoints
/// are ready — no other code needs to change.
final personalityRepositoryProvider = Provider<PersonalityRepository>(
  (ref) => MockPersonalityRepository(),
);

/// The signed-in user's current OCEAN result, if the quiz has been taken.
/// Used by ProfilePage and profile_review_page.dart's summary.
final myPersonalityResultProvider =
    FutureProvider.autoDispose<PersonalityResult?>((ref) {
  return ref.watch(personalityRepositoryProvider).getMyResult();
});

enum QuizPhase { intro, question, result }

class PersonalityQuizState {
  final QuizPhase phase;
  final Quiz? quiz;
  final int currentIndex;
  final Map<String, int> answers; // questionId -> score (1-5)
  final PersonalityResult? result;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  const PersonalityQuizState({
    this.phase = QuizPhase.intro,
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

  PersonalityQuizState copyWith({
    QuizPhase? phase,
    Quiz? quiz,
    int? currentIndex,
    Map<String, int>? answers,
    PersonalityResult? result,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
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

/// Drives the Discover-your-personality sub-flow: intro card -> one
/// question per screen -> OCEAN result. Entirely independent of
/// registration state.
final personalityQuizProvider = NotifierProvider.autoDispose<
    PersonalityQuizNotifier, PersonalityQuizState>(
  PersonalityQuizNotifier.new,
);

class PersonalityQuizNotifier
    extends AutoDisposeNotifier<PersonalityQuizState> {
  @override
  PersonalityQuizState build() => const PersonalityQuizState();

  Future<void> startQuiz() async {
    state = state.copyWith(phase: QuizPhase.question, isLoading: true);
    try {
      final quiz = await ref.read(personalityRepositoryProvider).getQuizQuestions();
      state = state.copyWith(quiz: quiz, isLoading: false);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load the quiz. Check your connection.',
      );
    }
  }

  void answer(String questionId, int score) {
    state = state.copyWith(answers: {...state.answers, questionId: score});
  }

  void nextQuestion() {
    if (state.quiz == null) return;
    if (state.currentIndex < state.quiz!.questions.length - 1) {
      state = state.copyWith(currentIndex: state.currentIndex + 1);
    }
  }

  void previousQuestion() {
    if (state.currentIndex > 0) {
      state = state.copyWith(currentIndex: state.currentIndex - 1);
    }
  }

  Future<void> submit() async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final result = await ref
          .read(personalityRepositoryProvider)
          .submitPersonalityQuiz(state.answers);
      state = state.copyWith(
        isSubmitting: false,
        result: result,
        phase: QuizPhase.result,
      );
      ref.invalidate(myPersonalityResultProvider);
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'Could not submit the quiz. Check your connection.',
      );
    }
  }
}
