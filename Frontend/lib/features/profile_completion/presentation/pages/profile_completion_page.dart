import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/checklist_item_card.dart';
import '../../../../core/widgets/cards/growth_card.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../../registration/presentation/utils/open_edit_profile.dart';
import '../../domain/profile_completion_aggregator.dart';
import '../providers/profile_completeness_provider.dart';
import '../utils/module_copy.dart';

/// "Profile Strength" — a growth-journey hub, not a checklist: overall
/// strength, the single highest-impact improvement, what's already done,
/// what's still growing, and an always-on "keep growing" surface pointing
/// at Nenjam's other Relationship Intelligence features.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Headline percentage comes from the backend — the single source of truth
    // shared with the Profile page, Edit Profile, and Discover. The module
    // breakdown below still uses the aggregator to show which sections remain.
    final pct = ref.watch(backendProfileCompletionProvider).valueOrNull ??
        completeness.percentage;
    final highestImpact = completeness.highestImpactModule;
    // "Still Growing" excludes the module already featured above, so it
    // isn't shown twice on the same screen.
    final stillGrowing = completeness.missingModules
        .where((e) => e.module.id != highestImpact?.module.id)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.profileCompletionScreenSubtitle,
            style: AppTypography.bodyMedium.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 24),
          _StrengthHero(completeness: completeness, percentage: pct),
          if (highestImpact != null) ...[
            const SizedBox(height: 24),
            Text(l10n.profileCompletionHighestImpactLabel,
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _HighestImpactCard(evaluated: highestImpact),
          ],
          if (completeness.completedModules.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(l10n.profileCompletionCompletedSectionsTitle,
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final e in completeness.completedModules)
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
          if (stillGrowing.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(l10n.profileCompletionMissingSectionsTitle,
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.w700)),
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
                  onAction: () => openEditProfile(context, ref,
                      wizardStep: e.status.wizardStep),
                ),
              ),
          ],
          const SizedBox(height: 32),
          Text(l10n.profileCompletionFutureGrowthTitle,
              style: AppTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            l10n.profileCompletionFutureGrowthSubtitle,
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
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
            icon: Icons.chat_bubble_outline_rounded,
            title: l10n.profileCompletionGrowthPrompts,
            subtitle: l10n.profileCompletionGrowthPromptsSubtitle,
            onTap: () => context.push(RouteNames.choosePrompt, extra: const []),
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

// ─── Module → display copy (small switch, not business logic) ────────────

String _tierLabel(AppLocalizations l10n, ProfileStrengthTier tier) => switch (tier) {
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
                style: AppTypography.displaySmall
                    .copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _tierLabel(l10n, completeness.tier),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.accentGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percentage / 100,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              color: AppColors.accentGold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Highest impact callout ───────────────────────────────────────────

class _HighestImpactCard extends ConsumerWidget {
  final EvaluatedModule evaluated;

  const _HighestImpactCard({required this.evaluated});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.goldBorder.copyWith(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(moduleIcon(evaluated.module.id),
                color: AppColors.accentGold, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  moduleAction(l10n, evaluated.module.id),
                  style: AppTypography.titleSmall
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  moduleTip(l10n, evaluated.module.id),
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => openEditProfile(context, ref,
                wizardStep: evaluated.status.wizardStep),
            icon: const Icon(Icons.arrow_forward_rounded,
                color: AppColors.accentGold),
          ),
        ],
      ),
    );
  }
}

