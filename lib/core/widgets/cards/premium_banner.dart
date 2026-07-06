import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_gradients.dart';
import '../../theme/app_typography.dart';

/// Premium banner card for upgrade CTA.
///
/// String props are optional; when null, localized defaults are used.
class NmPremiumBanner extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onTap;

  const NmPremiumBanner({
    super.key,
    this.title,
    this.subtitle,
    this.actionLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = this.title ?? l10n.premiumBannerTitle;
    final subtitle = this.subtitle ?? l10n.premiumBannerSubtitle;
    final actionLabel = this.actionLabel ?? l10n.premiumBannerCta;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppGradients.premiumCard,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: AppColors.accentGold, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                gradient: AppGradients.gold,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                actionLabel,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textOnGold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
