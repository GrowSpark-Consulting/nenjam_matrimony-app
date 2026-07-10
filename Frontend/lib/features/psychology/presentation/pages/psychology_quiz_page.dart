import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/outlined_button.dart';
import '../../../../core/widgets/relationship_intelligence/psychology_section.dart';
import '../../domain/models/personality_result.dart';
import '../providers/personality_provider.dart';

/// "Discover your personality" — OCEAN Big-Five quiz sub-flow. Three
/// phases in one page: an intro card, one Likert question per screen, and
/// a result screen with trait bars. Pops a [PersonalityResult] on
/// successful completion so callers can refresh their own display state.
class PsychologyQuizPage extends ConsumerWidget {
  const PsychologyQuizPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(personalityQuizProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Personality Quiz')),
      body: SafeArea(
        child: switch (state.phase) {
          QuizPhase.intro => const _IntroView(),
          QuizPhase.question => const _QuestionView(),
          QuizPhase.result => const _ResultView(),
        },
      ),
    );
  }
}

// ─── Intro ──────────────────────────────────────────────────────────────

class _IntroView extends ConsumerWidget {
  const _IntroView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Container(
            padding: AppSpacing.cardPaddingLarge,
            decoration: AppDecorations.premiumCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.psychology_alt_rounded,
                      color: AppColors.accentGold, size: 30),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Discover your personality',
                  style: AppTypography.headlineSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'A short OCEAN Big-Five assessment. Your results help us '
                  'suggest more compatible matches.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      'Takes about 3 minutes',
                      style: AppTypography.labelMedium
                          .copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          NmGradientButton(
            label: 'Start Quiz',
            useGoldGradient: true,
            icon: Icons.play_arrow_rounded,
            onPressed: () => ref.read(personalityQuizProvider.notifier).startQuiz(),
          ),
          const SizedBox(height: AppSpacing.base),
        ],
      ),
    );
  }
}

// ─── Question ───────────────────────────────────────────────────────────

class _QuestionView extends ConsumerWidget {
  const _QuestionView();

  static const _likertLabels = [
    'Strongly Disagree',
    'Disagree',
    'Neutral',
    'Agree',
    'Strongly Agree',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(personalityQuizProvider);
    final notifier = ref.read(personalityQuizProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.quiz == null) {
      return Center(
        child: Padding(
          padding: AppSpacing.pagePadding,
          child: Text(state.error!, textAlign: TextAlign.center),
        ),
      );
    }
    final quiz = state.quiz;
    if (quiz == null || quiz.questions.isEmpty) {
      return const Center(child: Text('No quiz is available right now.'));
    }

    final question = quiz.questions[state.currentIndex];
    final selectedScore = state.answers[question.id];

    return Padding(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppSpacing.borderRadiusFull,
            child: LinearProgressIndicator(
              value: (state.currentIndex + 1) / quiz.questions.length,
              minHeight: 6,
              backgroundColor: isDark
                  ? AppColors.surfaceVariantDark
                  : AppColors.surfaceVariantLight,
              valueColor: const AlwaysStoppedAnimation(AppColors.accentGold),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Question ${state.currentIndex + 1} of ${quiz.questions.length}',
            style: AppTypography.labelMedium.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: AppSpacing.xl2),
          Text(
            question.questionText,
            style: AppTypography.headlineSmall
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xl2),
          ...List.generate(5, (i) {
            final score = i + 1;
            final selected = selectedScore == score;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: InkWell(
                borderRadius: AppSpacing.borderRadiusMd,
                onTap: () => notifier.answer(question.id, score),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : (isDark
                            ? AppColors.surfaceVariantDark
                            : AppColors.surfaceVariantLight),
                    borderRadius: AppSpacing.borderRadiusMd,
                    border: Border.all(
                      color: selected ? AppColors.primary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(_likertLabels[i], style: AppTypography.bodyLarge),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Row(
            children: [
              if (state.currentIndex > 0)
                Expanded(
                  child: NmOutlinedButton(
                    label: 'Back',
                    onPressed: notifier.previousQuestion,
                  ),
                ),
              if (state.currentIndex > 0) const SizedBox(width: AppSpacing.md),
              Expanded(
                child: NmGradientButton(
                  label: state.isLastQuestion ? 'Submit' : 'Next',
                  isLoading: state.isSubmitting,
                  onPressed: selectedScore == null
                      ? null
                      : () => state.isLastQuestion
                          ? notifier.submit()
                          : notifier.nextQuestion(),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

// ─── Result ─────────────────────────────────────────────────────────────

class _ResultView extends ConsumerWidget {
  const _ResultView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(personalityQuizProvider);
    final result = state.result ?? const PersonalityResult();

    return Padding(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.md),
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 48),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your Personality Profile',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: SingleChildScrollView(
              child: PsychologySection(result: result),
            ),
          ),
          NmGradientButton(
            label: 'Done',
            useGoldGradient: true,
            onPressed: () => context.pop(result),
          ),
          const SizedBox(height: AppSpacing.base),
        ],
      ),
    );
  }
}
