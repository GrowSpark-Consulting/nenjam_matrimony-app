import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';

/// Premium Membership upgrade card — deep plum banner with a cream crown
/// and an "Explore Elite" CTA integrated inside the card.
///
/// Deep plum rather than the magenta ramp: this is the largest premium
/// surface on the Profile screen, and a full magenta/rose fill made it the
/// pinkest element in the app while leaving its plum text at ~1.7:1. Plum
/// carries the depth, magenta is spent on the single CTA, and cream is the
/// luxury accent.
class NmPremiumMembershipCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String ctaLabel;
  final bool isPremiumMember;
  final VoidCallback? onCtaTap;

  const NmPremiumMembershipCard({
    super.key,
    this.title = 'Upgrade to Nenjam Elite',
    this.subtitle =
        'Get priority profile placement and verified personal concierge assistance.',
    this.ctaLabel = 'Explore Elite',
    this.isPremiumMember = false,
    this.onCtaTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppGradients.premiumCard,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl3),
        boxShadow: AppShadows.elevated,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Decorative crown watermark
          Positioned(
            right: -24,
            top: -24,
            child: Icon(
              Icons.workspace_premium_rounded,
              size: 140,
              color: AppColors.premiumCream.withValues(alpha: 0.10),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 550;

                final content = Row(
                  children: [
                    // Crown circle
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.premiumCream.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: AppColors.premiumCream,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.base * 4),

                    // Text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPremiumMember ? 'Nenjam Elite Member' : title,
                            style: AppTypography.titleMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isPremiumMember
                                ? 'You have full access to all premium features.'
                                : subtitle,
                            style: AppTypography.bodyMedium.copyWith(
                              color: Colors.white70,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final button = SizedBox(
                  width: isWide ? null : double.infinity,
                  child: ElevatedButton(
                    onPressed: onCtaTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                      ),
                      elevation: 4,
                      shadowColor: AppColors.secondaryDark.withValues(
                        alpha: 0.4,
                      ),
                    ),
                    child: Text(
                      ctaLabel,
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: content),
                      const SizedBox(width: AppSpacing.base * 4),
                      button,
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      content,
                      const SizedBox(height: AppSpacing.lg),
                      button,
                    ],
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
