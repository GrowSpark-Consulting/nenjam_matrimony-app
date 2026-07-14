import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';

/// Premium Membership upgrade card — gold gradient banner with crown icon
/// and a "Explore Elite" CTA button integrated inside the card.
///
/// Matches the Stitch "Personal Matchmaking HQ" design.
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
        gradient: AppGradients.gold,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl3),
        boxShadow: AppShadows.goldGlow,
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
              color: Colors.white.withValues(alpha: 0.12),
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
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: AppColors.primary,
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
                              color: AppColors.primary,
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
                              color: AppColors.primary.withValues(alpha: 0.8),
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
                      backgroundColor: AppColors.primary,
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
                      shadowColor: AppColors.primary.withValues(alpha: 0.3),
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
