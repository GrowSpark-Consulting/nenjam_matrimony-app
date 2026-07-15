import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/relationship_intelligence/psychology_section.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../psychology/domain/models/personality_result.dart';
import '../../../psychology/presentation/providers/personality_provider.dart';
import 'registration_helper_tip.dart';

/// Step 10 — Psychological Quiz.
///
/// A pure presentation adapter: it holds no quiz state, validation,
/// scoring, repository, provider, or synchronization logic of its own, and
/// it never writes to [registrationProvider]. Not a new quiz: this embeds
/// the existing OCEAN Big-Five flow owned by the psychology feature
/// (`PsychologyQuizPage`, `personalityQuizProvider`, `PersonalityRepository`)
/// so the wizard and Profile Intelligence share one implementation. It only
/// renders [PsychologySection] against [myPersonalityResultProvider] — the
/// same provider/widget pair already used on the profile review screen —
/// and pushes the same quiz route to take or retake it. Psychology remains
/// the single source of truth; anything registration-flow logic needs to
/// know about quiz completion is read on demand straight from there (see
/// `RegistrationNotifier.psychologyQuizResult`), not from this widget.
class StepPsychologicalQuiz extends ConsumerWidget {
  const StepPsychologicalQuiz({super.key});

  Future<void> _takeQuiz(BuildContext context, WidgetRef ref) async {
    await context.push(RouteNames.psychologyQuiz);
    ref.invalidate(myPersonalityResultProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final personalityAsync = ref.watch(myPersonalityResultProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.registrationWizardQuizHeadline,
            style: AppTypography.headlineSmall
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.registrationWizardQuizHook,
            style: AppTypography.bodyMedium.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipQuiz),
          const SizedBox(height: 24),
          personalityAsync.when(
            data: (result) => PsychologySection(
              result: result ?? const PersonalityResult(),
              onTakeQuizTap: () => _takeQuiz(context, ref),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => PsychologySection(
              result: const PersonalityResult(),
              onTakeQuizTap: () => _takeQuiz(context, ref),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
