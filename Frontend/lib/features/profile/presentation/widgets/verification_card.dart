import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// Verification status for a single item.
enum NmVerificationStatus { verified, pending, incomplete }

/// A single verification item (Phone, Email, Gov ID, Face Match).
class NmVerificationItem {
  final IconData icon;
  final String label;
  final NmVerificationStatus status;
  final VoidCallback? onTap;

  const NmVerificationItem({
    required this.icon,
    required this.label,
    required this.status,
    this.onTap,
  });
}

/// Verification Center card — 2×2 grid of verification items with
/// colour-coded status indicators (green = verified, gold = pending,
/// grey = incomplete).
class NmVerificationCard extends StatelessWidget {
  final List<NmVerificationItem> items;

  const NmVerificationCard({super.key, required this.items});

  /// Default verification items used when none are supplied.
  /// Takes an [AppLocalizations] because the labels are translated, so this
  /// can no longer be a compile-time constant.
  static List<NmVerificationItem> defaultsFor(AppLocalizations l10n) => [
    NmVerificationItem(
      icon: Icons.phone_iphone_rounded,
      label: l10n.fieldPhone,
      status: NmVerificationStatus.verified,
    ),
    NmVerificationItem(
      icon: Icons.mail_rounded,
      label: l10n.fieldEmail,
      status: NmVerificationStatus.verified,
    ),
    NmVerificationItem(
      icon: Icons.badge_rounded,
      label: l10n.fieldGovId,
      status: NmVerificationStatus.pending,
    ),
    NmVerificationItem(
      icon: Icons.face_rounded,
      label: l10n.fieldFaceMatch,
      status: NmVerificationStatus.incomplete,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl2),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.borderLight.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_rounded,
                color: AppColors.verifiedBlue,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).drawerVerificationCenter,
                  style: AppTypography.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          // A Wrap of half-width tiles sizes to its content height, so
          // tiles never clip when text grows under large font scaling —
          // unlike a fixed-aspect-ratio GridView.
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth =
                  (constraints.maxWidth - AppSpacing.sm) / 2;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: items
                    .map(
                      (item) => SizedBox(
                        width: tileWidth,
                        child: _VerifTile(item: item, isDark: isDark),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _VerifTile extends StatelessWidget {
  final NmVerificationItem item;
  final bool isDark;

  const _VerifTile({required this.item, required this.isDark});

  Color get _borderColor {
    switch (item.status) {
      case NmVerificationStatus.verified:
        return AppColors.faceVerificationGreen;
      case NmVerificationStatus.pending:
        return AppColors.accentGold;
      case NmVerificationStatus.incomplete:
        return AppColors.disabled;
    }
  }

  Color get _iconColor {
    switch (item.status) {
      case NmVerificationStatus.verified:
        return AppColors.faceVerificationGreen;
      case NmVerificationStatus.pending:
        return AppColors.accentGold;
      case NmVerificationStatus.incomplete:
        return AppColors.disabled;
    }
  }

  String _statusLabelOf(AppLocalizations l10n) {
    switch (item.status) {
      case NmVerificationStatus.verified:
        return l10n.discoverVerifiedLabel;
      case NmVerificationStatus.pending:
        return l10n.verificationStatusPending;
      case NmVerificationStatus.incomplete:
        return l10n.verificationStatusIncomplete;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border(top: BorderSide(color: _borderColor, width: 2)),
        ),
        child: Row(
          children: [
            Icon(item.icon, size: 20, color: _iconColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.label,
                    style: AppTypography.labelMedium.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _statusLabelOf(AppLocalizations.of(context)).toUpperCase(),
                    style: AppTypography.labelSmall.copyWith(
                      color: _iconColor,
                      fontSize: 9,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
