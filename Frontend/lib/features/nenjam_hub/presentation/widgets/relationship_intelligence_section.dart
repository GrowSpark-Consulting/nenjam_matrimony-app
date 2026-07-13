import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/intelligence_card.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../astro/presentation/providers/compatibility_provider.dart';
import '../../../psychology/domain/models/personality_result.dart';
import '../../../psychology/presentation/providers/personality_provider.dart';
import '../../../registration/presentation/utils/open_edit_profile.dart';

/// Section 2 — Relationship Intelligence. Reuses the same profile-intelligence
/// data (psychology, horoscope) already surfaced elsewhere in the app, plus
/// two "coming soon" locked cards for future dimensions.
class RelationshipIntelligenceSection extends ConsumerWidget {
  const RelationshipIntelligenceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final personalityAsync = ref.watch(myPersonalityResultProvider);
    final horoscopeAsync = ref.watch(myHoroscopeSummaryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.nenjamHubRelationshipIntelligenceTitle,
            style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(l10n.nenjamHubRelationshipIntelligenceSubtitle,
            style: AppTypography.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        NmIntelligenceCard(
          icon: Icons.psychology_alt_rounded,
          title: l10n.nenjamHubCardPsychology,
          subtitle: personalityAsync.when(
            data: (result) => (result?.completed ?? false)
                ? _communicationStyle(result!)
                : l10n.profileCompletionGrowthPsychologySubtitle,
            loading: () => '…',
            error: (_, __) => l10n.profileCompletionGrowthPsychologySubtitle,
          ),
          onTap: () async {
            await context.push(RouteNames.psychologyQuiz);
            ref.invalidate(myPersonalityResultProvider);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        NmIntelligenceCard(
          icon: Icons.auto_awesome_rounded,
          title: l10n.nenjamHubCardAstrology,
          subtitle: horoscopeAsync.when(
            data: (summary) =>
                summary.matchingEnabled ? 'Matching enabled' : 'Matching disabled',
            loading: () => '…',
            error: (_, __) => l10n.profileCompletionGrowthHoroscopeSubtitle,
          ),
          onTap: () async {
            await context.push(RouteNames.horoscopeMatching);
            ref.invalidate(myHoroscopeSummaryProvider);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        NmIntelligenceCard(
          icon: Icons.forum_rounded,
          title: l10n.nenjamHubCardCommunication,
          subtitle: personalityAsync.when(
            data: (result) => (result?.completed ?? false)
                ? _communicationStyle(result!)
                : l10n.nenjamHubCardCommunicationSubtitle,
            loading: () => '…',
            error: (_, __) => l10n.nenjamHubCardCommunicationSubtitle,
          ),
          onTap: () async {
            await context.push(RouteNames.psychologyQuiz);
            ref.invalidate(myPersonalityResultProvider);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        NmIntelligenceCard(
          icon: Icons.spa_rounded,
          title: l10n.nenjamHubCardLifestyle,
          subtitle: l10n.nenjamHubCardLifestyleSubtitle,
          onTap: () => openEditProfile(context, ref, wizardStep: 6),
        ),
        const SizedBox(height: AppSpacing.md),
        NmIntelligenceCard(
          icon: Icons.flag_rounded,
          title: l10n.nenjamHubCardFutureGoals,
          subtitle: l10n.nenjamHubCardFutureGoalsSubtitle,
          onTap: () => openEditProfile(context, ref, wizardStep: 9),
        ),
        const SizedBox(height: AppSpacing.md),
        NmIntelligenceCard(
          icon: Icons.favorite_rounded,
          title: l10n.nenjamHubCardLoveLanguage,
          subtitle: l10n.nenjamHubComingSoon,
          locked: true,
          onTap: () {},
        ),
        const SizedBox(height: AppSpacing.md),
        NmIntelligenceCard(
          icon: Icons.anchor_rounded,
          title: l10n.nenjamHubCardAttachmentStyle,
          subtitle: l10n.nenjamHubComingSoon,
          locked: true,
          onTap: () {},
        ),
      ],
    );
  }

  /// Derives a friendly communication-style label from the user's own OCEAN
  /// result — no new backend field, just a different lens on existing data.
  String _communicationStyle(PersonalityResult result) {
    if (result.extraversion > 60) return 'Expressive & direct';
    if (result.agreeableness > 60) return 'Warm & thoughtful';
    return 'Calm & considered';
  }
}
