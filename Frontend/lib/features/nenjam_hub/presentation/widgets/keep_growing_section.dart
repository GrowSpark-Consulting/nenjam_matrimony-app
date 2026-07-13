import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/growth_card.dart';
import '../../../../l10n/app_localizations.dart';

/// Bottom "Keep Growing" journey strip — the same "improve yourself"
/// framing and card as the Profile Completion screen, extended with two
/// more entries (Voice Introduction, Trust Score).
class KeepGrowingSection extends StatelessWidget {
  const KeepGrowingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.profileCompletionFutureGrowthTitle,
            style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(l10n.profileCompletionFutureGrowthSubtitle,
            style: AppTypography.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        NmGrowthCard(
          icon: Icons.psychology_alt_rounded,
          title: l10n.profileCompletionGrowthPsychology,
          subtitle: l10n.profileCompletionGrowthPsychologySubtitle,
          onTap: () => context.push(RouteNames.psychologyQuiz),
        ),
        const SizedBox(height: AppSpacing.md),
        NmGrowthCard(
          icon: Icons.stars_rounded,
          title: l10n.profileCompletionGrowthHoroscope,
          subtitle: l10n.profileCompletionGrowthHoroscopeSubtitle,
          onTap: () => context.push(RouteNames.horoscopeMatching),
        ),
        const SizedBox(height: AppSpacing.md),
        NmGrowthCard(
          icon: Icons.chat_bubble_outline_rounded,
          title: l10n.profileCompletionGrowthPrompts,
          subtitle: l10n.profileCompletionGrowthPromptsSubtitle,
          onTap: () => context.push(RouteNames.choosePrompt, extra: const []),
        ),
        const SizedBox(height: AppSpacing.md),
        NmGrowthCard(
          icon: Icons.mic_rounded,
          title: l10n.nenjamHubGrowthVoiceIntro,
          subtitle: l10n.nenjamHubGrowthVoiceIntroSubtitle,
          onTap: () {},
        ),
        const SizedBox(height: AppSpacing.md),
        NmGrowthCard(
          icon: Icons.verified_user_rounded,
          title: l10n.nenjamHubGrowthTrustScore,
          subtitle: l10n.nenjamHubGrowthTrustScoreSubtitle,
          onTap: () => context.push(RouteNames.trustScore),
        ),
        const SizedBox(height: AppSpacing.md),
        NmGrowthCard(
          icon: Icons.workspace_premium_rounded,
          title: l10n.profileCompletionGrowthPremium,
          subtitle: l10n.profileCompletionGrowthPremiumSubtitle,
          onTap: () => context.go(RouteNames.premium),
        ),
      ],
    );
  }
}
