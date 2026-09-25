import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/outlined_button.dart';
import '../../../../core/widgets/relationship_intelligence/psychology_section.dart';
import '../../domain/models/personality_result.dart';
import '../providers/personality_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Marriage Compatibility (psychology) quiz sub-flow. Phases in one page: an
/// intro card, one single-select question per screen (options come from
/// `GET /psychology/quiz/active`), and a completed state listing the user's
/// saved answers with a retake action. A user who has already completed the
/// current quiz opens straight at the completed state. There is no
/// single-user score to show — compatibility is scored server-side, pairwise.
class PsychologyQuizPage extends ConsumerWidget {
  const PsychologyQuizPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(personalityQuizProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).psychologyQuizTitle),
      ),
      body: SafeArea(
        child: switch (state.phase) {
          QuizPhase.checking =>
            state.error == QuizError.checkFailed
                ? const _CheckFailedView()
                : const Center(child: CircularProgressIndicator()),
          QuizPhase.intro => const _IntroView(),
          QuizPhase.question => const _QuestionView(),
          QuizPhase.result => const _ResultView(),
        },
      ),
    );
  }
}

// ─── Checking failed ────────────────────────────────────────────────────

/// `GET /me` failed for a reason other than 404, so whether the user
/// already has saved answers is unknown. Offer a retry rather than the
/// intro — see [QuizError.checkFailed]. The app bar's back still works.
class _CheckFailedView extends ConsumerWidget {
  const _CheckFailedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.psychologyCheckError,
              key: const ValueKey('psychology-check-error'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            NmOutlinedButton(
              label: l10n.commonRetry,
              onPressed: ref.read(personalityQuizProvider.notifier).retryCheck,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Intro ──────────────────────────────────────────────────────────────

class _IntroView extends ConsumerWidget {
  const _IntroView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same Spacer-centred layout as always; it only scrolls when the card
    // can't fit (small screens, landscape, longer Tamil copy).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: _introBody(context, ref)),
        ),
      ),
    );
  }

  Widget _introBody(BuildContext context, WidgetRef ref) {
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
                  child: const Icon(
                    Icons.psychology_alt_rounded,
                    color: AppColors.secondary,
                    size: 30,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  AppLocalizations.of(context).riDiscoverPersonality,
                  style: AppTypography.headlineSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  AppLocalizations.of(context).psychologyIntroBody,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        AppLocalizations.of(context).psychologyTakesMinutes,
                        style: AppTypography.labelMedium.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          NmGradientButton(
            label: AppLocalizations.of(context).psychologyStartQuiz,
            useAccentGradient: true,
            icon: Icons.play_arrow_rounded,
            onPressed: () =>
                ref.read(personalityQuizProvider.notifier).startQuiz(),
          ),
          const SizedBox(height: AppSpacing.base),
        ],
      ),
    );
  }
}

// ─── Question ───────────────────────────────────────────────────────────

/// Localized "you can change your answers again in …" for a retake cooldown
/// of [seconds] (the server's `retryAfterSeconds`). Rounds up, so a positive
/// wait never reads as zero: under a day it's whole hours (at least 1),
/// otherwise whole days. The server's own English `message` is never shown.
String psychologyRetakeCooldownMessage(AppLocalizations l10n, int seconds) {
  final wait = seconds < 1 ? 1 : seconds;
  if (wait < Duration.secondsPerDay) {
    return l10n.psychologyRetakeCooldownHours(
      (wait / Duration.secondsPerHour).ceil(),
    );
  }
  return l10n.psychologyRetakeCooldownDays(
    (wait / Duration.secondsPerDay).ceil(),
  );
}

String _errorText(AppLocalizations l10n, PersonalityQuizState state) =>
    switch (state.error!) {
      QuizError.checkFailed => l10n.psychologyCheckError,
      QuizError.unavailable => l10n.psychologyNoQuiz,
      QuizError.loadFailed => l10n.psychologyLoadError,
      QuizError.incomplete => l10n.psychologyIncompleteError,
      QuizError.rejected => l10n.psychologyRejectedError,
      QuizError.retakeCooldown => psychologyRetakeCooldownMessage(
        l10n,
        state.cooldownSeconds ?? 1,
      ),
      QuizError.rateLimited => l10n.apiError429,
      QuizError.submitFailed => l10n.psychologySubmitError,
    };

class _QuestionView extends ConsumerWidget {
  const _QuestionView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(personalityQuizProvider);
    final notifier = ref.read(personalityQuizProvider.notifier);
    final l10n = AppLocalizations.of(context);

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final quiz = state.quiz;
    if (quiz == null || quiz.questions.isEmpty) {
      final error = state.error;
      return Center(
        child: Padding(
          padding: AppSpacing.pagePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error != null ? _errorText(l10n, state) : l10n.psychologyNoQuiz,
                textAlign: TextAlign.center,
              ),
              if (error == QuizError.loadFailed) ...[
                const SizedBox(height: AppSpacing.md),
                NmOutlinedButton(
                  label: l10n.commonRetry,
                  onPressed: notifier.startQuiz,
                ),
              ],
            ],
          ),
        ),
      );
    }

    final question = quiz.questions[state.currentIndex];
    final selectedKey = state.answers[question.id];

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
              backgroundColor: AppColors.surfaceVariantLight,
              valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.psychologyQuestionProgress(
              state.currentIndex + 1,
              quiz.questions.length,
            ),
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textSecondaryLight,
            ),
          ),
          // Long questions/options (and 320dp screens) scroll here, while the
          // progress header and the Back/Next row stay pinned.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.xl2),
                  Text(
                    question.questionText,
                    style: AppTypography.headlineSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl2),
                  for (final option in question.options)
                    _OptionCard(
                      key: ValueKey('psychology-option-${option.key}'),
                      label: option.label,
                      selected: selectedKey == option.key,
                      onTap: () => notifier.answer(question.id, option.key),
                    ),
                ],
              ),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _errorText(l10n, state),
              key: const ValueKey('psychology-error'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (state.currentIndex > 0)
                Expanded(
                  child: NmOutlinedButton(
                    label: l10n.registrationBack,
                    onPressed: notifier.previousQuestion,
                  ),
                ),
              if (state.currentIndex > 0) const SizedBox(width: AppSpacing.md),
              Expanded(
                child: NmGradientButton(
                  label: state.isLastQuestion
                      ? l10n.psychologySubmit
                      : l10n.psychologyNext,
                  isLoading: state.isSubmitting,
                  // No resubmitting into an active cooldown; changing an
                  // answer clears the error and re-enables it.
                  onPressed:
                      selectedKey == null ||
                          state.error == QuizError.retakeCooldown
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

/// One answer choice — the same card treatment the quiz has always used
/// (tinted fill + primary border when selected, radio icon). The label wraps
/// instead of overflowing, since real option labels run to two or three
/// lines on narrow screens.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: AppSpacing.borderRadiusMd,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.surfaceVariantLight,
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
                    : AppColors.textTertiaryLight,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label, style: AppTypography.bodyLarge)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Completed ──────────────────────────────────────────────────────────

class _ResultView extends ConsumerWidget {
  const _ResultView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(personalityQuizProvider);
    final result = state.result;
    final l10n = AppLocalizations.of(context);
    final updated = PsychologySection.updatedLabel(l10n, result?.lastUpdatedAt);
    final notifier = ref.read(personalityQuizProvider.notifier);

    // Retake gating. After a 429 the server's figure is authoritative and
    // there is no way round it. Otherwise it's only a client hint
    // (`completedAt` + the default cooldown — the real length is server
    // config), so "Try anyway" still lets the server decide on submit.
    final now = ref.watch(psychologyClockProvider)();
    final availableAt = state.retakeAvailableAt;
    final waiting = availableAt != null && now.isBefore(availableAt);
    final serverSaysWait = waiting && state.serverRetakeAvailableAt != null;
    final String? waitText = !waiting
        ? null
        : serverSaysWait
        ? psychologyRetakeCooldownMessage(
            l10n,
            (availableAt.difference(now).inMilliseconds / 1000).ceil(),
          )
        : l10n.psychologyRetakeAvailableOn(
            DateFormat.yMMMd(l10n.localeName).format(availableAt.toLocal()),
          );

    return Padding(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.md),
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.success,
            size: 48,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.psychologyYourProfile,
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (updated != null) ...[
            const SizedBox(height: 4),
            Text(
              updated,
              textAlign: TextAlign.center,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: SingleChildScrollView(
              child: _AnswersCard(answers: result?.answers ?? const []),
            ),
          ),
          if (waitText != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              waitText,
              key: const ValueKey('psychology-retake-wait'),
              textAlign: TextAlign.center,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
            if (!serverSaysWait)
              Center(
                child: TextButton(
                  key: const ValueKey('psychology-retake-try-anyway'),
                  onPressed: notifier.retake,
                  child: Text(l10n.psychologyRetakeTryAnyway),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: NmOutlinedButton(
                  key: const ValueKey('psychology-retake'),
                  label: l10n.psychologyRetakeQuiz,
                  onPressed: waiting ? null : notifier.retake,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: NmGradientButton(
                  label: l10n.commonDone,
                  useAccentGradient: true,
                  onPressed: () => context.pop(result),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
        ],
      ),
    );
  }
}

/// The user's own saved answers (question -> chosen option), in the same
/// card chrome as [PsychologySection].
class _AnswersCard extends StatelessWidget {
  const _AnswersCard({required this.answers});

  final List<PsychologyQuizAnswer> answers;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPaddingLarge,
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.psychology_alt_rounded,
                color: AppColors.scorePsychology,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).psychologyYourAnswers,
                  style: AppTypography.titleSmall,
                ),
              ),
            ],
          ),
          for (final answer in answers) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              answer.questionText,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              answer.selectedLabel,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
