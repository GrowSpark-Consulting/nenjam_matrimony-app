import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// AI Match Coach card — deep navy full-bleed card with coaching insights
/// and a call-to-action to improve the user's profile.
///
/// Matches the Stitch "Personal Matchmaking HQ" design section 3.
class NmAiMatchCoachCard extends StatelessWidget {
  final String headline;
  final String subtitle;
  final List<String> suggestions;
  final String ctaLabel;
  final VoidCallback? onCtaTap;

  const NmAiMatchCoachCard({
    super.key,
    this.headline = "You're outperforming 74% of peers",
    this.subtitle =
        'Our intelligence suggests these adjustments to unlock high-intent matches this week.',
    this.suggestions = const [
      'Upload a natural smiling photo',
      'Expand bio with lifestyle interests',
    ],
    this.ctaLabel = 'Improve My Profile',
    this.onCtaTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppGradients.premiumCard,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Decorative watermark icon (top-right, low opacity)
          Positioned(
            top: -10,
            right: -10,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 140,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section label
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.accentGoldLight,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        AppLocalizations.of(context).profileAiMatchCoach,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.accentGoldLight,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.md),

                // Headline
                Text(
                  headline,
                  style: AppTypography.titleLarge.copyWith(color: Colors.white),
                ),

                const SizedBox(height: AppSpacing.sm),

                // Subtitle
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: AppSpacing.base),

                // Suggestion bullets
                ...suggestions.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.faceVerificationGreen,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            s,
                            style: AppTypography.labelMedium.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // CTA button
                GestureDetector(
                  onTap: onCtaTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppGradients.gold,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentGold.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      ctaLabel,
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.textOnGold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
