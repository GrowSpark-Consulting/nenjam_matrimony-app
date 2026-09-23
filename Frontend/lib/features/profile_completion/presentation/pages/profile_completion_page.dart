import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/indicators/nm_gradient_progress_bar.dart';
import '../../../../core/widgets/cards/checklist_item_card.dart';
import '../../../../core/widgets/cards/growth_card.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../registration/presentation/utils/open_edit_profile.dart';
import '../../domain/profile_completion_aggregator.dart';
import '../providers/profile_completeness_provider.dart';
import '../utils/module_copy.dart';

/// "Profile Strength" — a growth-journey hub answering exactly one question:
/// *how complete is my profile?* Overall completion, what's already done,
/// what's still growing, and an always-on "keep growing" surface pointing
/// at Nenjam's other Relationship Intelligence features.
///
/// Verification is a separate concept and is deliberately absent here: no
/// verification recommendation and no verification callout.
class ProfileCompletionPage extends ConsumerWidget {
  const ProfileCompletionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(profileCompletenessSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileCompletionScreenTitle)),
      body: async.when(
        data: (completeness) =>
            _ProfileCompletionBody(completeness: completeness),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: NmErrorWidget(
            onRetry: () => ref.invalidate(profileCompletenessSnapshotProvider),
          ),
        ),
      ),
    );
  }
}

class _ProfileCompletionBody extends ConsumerWidget {
  final ProfileCompleteness completeness;

  const _ProfileCompletionBody({required this.completeness});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Headline percentage IS the backend's `completionPercentage`, carried
    // through untouched by [profileCompletenessFromBackend] — the very same
    // number the Profile dashboard, Edit Profile, and Discover show. Nothing
    // on this screen recomputes it from the cards below, so filtering or
    // reordering a section never moves the figure.
    final pct = completeness.percentage;
    final completed =
        completeness.completedModules.where(_isCompletionSection).toList();
    final stillGrowing =
        completeness.missingModules.where(_isCompletionSection).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.profileCompletionScreenSubtitle,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 24),
          _StrengthHero(completeness: completeness, percentage: pct),
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(
              l10n.profileCompletionCompletedSectionsTitle,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final e in completed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NmChecklistItemCard(
                  icon: moduleIcon(e.module.id),
                  title: moduleTitle(l10n, e.module.id),
                  subtitle: moduleTip(l10n, e.module.id),
                  actionLabel: '',
                  isDone: true,
                  onAction: () {},
                ),
              ),
          ],
          // Registration information. Shown ONLY when the backend says the
          // slice is incomplete: a member who just finished signing up has
          // answered all of it, and re-listing what they have already given
          // is the nagging this whole change exists to stop. A legacy profile
          // that genuinely lacks answers still sees exactly those, named and
          // deep-linked to the step that fixes each. The optional
          // sub-community never appears — missingRequiredFields excludes it.
          if (!completeness.registrationComplete &&
              completeness.missingRequiredFields.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(
              l10n.profileCompletionRegistrationGroupTitle,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final field in completeness.missingRequiredFields)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NmChecklistItemCard(
                  icon: moduleIcon('registration'),
                  title: requiredFieldTitle(l10n, field.id),
                  subtitle: '',
                  actionLabel: moduleAction(l10n, 'registration'),
                  isDone: false,
                  onAction: () => openEditProfile(
                    context,
                    ref,
                    wizardStep: field.wizardStep,
                  ),
                ),
              ),
          ],
          if (stillGrowing.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(
              l10n.profileCompletionMissingSectionsTitle,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final e in stillGrowing)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NmChecklistItemCard(
                  icon: moduleIcon(e.module.id),
                  title: moduleTitle(l10n, e.module.id),
                  subtitle: moduleTip(l10n, e.module.id),
                  actionLabel: moduleAction(l10n, e.module.id),
                  isDone: false,
                  onAction: () => openEditProfile(
                    context,
                    ref,
                    wizardStep: e.status.wizardStep,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 32),
          Text(
            l10n.profileCompletionFutureGrowthTitle,
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.profileCompletionFutureGrowthSubtitle,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 12),
          NmGrowthCard(
            icon: Icons.psychology_alt_rounded,
            title: l10n.profileCompletionGrowthPsychology,
            subtitle: l10n.profileCompletionGrowthPsychologySubtitle,
            onTap: () => context.push(RouteNames.psychologyQuiz),
          ),
          const SizedBox(height: 12),
          NmGrowthCard(
            icon: Icons.stars_rounded,
            title: l10n.profileCompletionGrowthHoroscope,
            subtitle: l10n.profileCompletionGrowthHoroscopeSubtitle,
            onTap: () => context.push(RouteNames.horoscopeMatching),
          ),
          const SizedBox(height: 12),
          NmGrowthCard(
            icon: Icons.workspace_premium_rounded,
            title: l10n.profileCompletionGrowthPremium,
            subtitle: l10n.profileCompletionGrowthPremiumSubtitle,
            onTap: () => context.go(RouteNames.premium),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Which modules this screen shows ─────────────────────────────────────

/// Profile Strength shows profile-*completion* sections only. The backend's
/// `verification` module is scored as part of the completion percentage (and
/// stays that way — the backend calculation is untouched), but every piece of
/// copy attached to it is verification-framed ("Get Verified", "Verified
/// profiles earn better responses…"), which is a different concept from "how
/// complete is my profile". So it is filtered out of this screen's cards
/// while still being counted in the headline percentage above.
///
/// `registration` is excluded too, but for a different reason: it is rendered
/// as its own field-by-field group above, so a generic "Registration" card
/// here would say the same thing twice and less usefully.
bool _isCompletionSection(EvaluatedModule e) =>
    e.module.id != 'verification' && e.module.id != 'registration';

// ─── Module → display copy (small switch, not business logic) ────────────

String _tierLabel(AppLocalizations l10n, ProfileStrengthTier tier) =>
    switch (tier) {
      ProfileStrengthTier.building => l10n.profileCompletionTierBuilding,
      ProfileStrengthTier.good => l10n.profileCompletionTierGood,
      ProfileStrengthTier.strong => l10n.profileCompletionTierStrong,
      ProfileStrengthTier.exceptional => l10n.profileCompletionTierExceptional,
    };

// ─── Hero ──────────────────────────────────────────────────────────────

class _StrengthHero extends StatelessWidget {
  final ProfileCompleteness completeness;
  // Backend-computed percentage (single source of truth). The tier/module
  // breakdown still comes from [completeness].
  final int percentage;

  const _StrengthHero({required this.completeness, required this.percentage});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppDecorations.premiumCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$percentage%',
                style: AppTypography.displaySmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _tierLabel(l10n, completeness.tier),
                    style: AppTypography.labelMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          NmGradientProgressBar(
            value: percentage / 100,
            gradient: AppGradients.match,
            trackColor: Colors.white.withValues(alpha: 0.15),
          ),
        ],
      ),
    );
  }
}
