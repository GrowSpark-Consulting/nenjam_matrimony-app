import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/compatibility_entity.dart';

/// Compact "87% match" pill — used inline next to the name row (single badge).
class CompatibilityBadge extends StatelessWidget {
  final CompatibilityEntity compatibility;

  const CompatibilityBadge({super.key, required this.compatibility});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.5;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: _GlassBadge(
        icon: Icons.bolt_rounded,
        iconColor: AppColors.accentGoldLight,
        label: '${compatibility.aiMatchPercent}% ${l10n.discoverAiMatchLabel}',
      ),
    );
  }
}

/// Row of score badges shown at the top of the reel card:
///   ⚡ 98% AI Match   ✦ 92% Astro   🛡 95 Trust Score
///
/// Renders left-aligned with auto-wrap so it never overflows.
/// Only shows badges for non-zero scores.
class CompatibilityBadgeRow extends StatelessWidget {
  final CompatibilityEntity compatibility;
  final bool isVerified;
  final bool isPremium;

  const CompatibilityBadgeRow({
    super.key,
    required this.compatibility,
    this.isVerified = false,
    this.isPremium = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final badges = <Widget>[];

    if (compatibility.aiMatchPercent > 0) {
      badges.add(_GlassBadge(
        icon: Icons.bolt_rounded,
        iconColor: AppColors.accentGoldLight,
        label: '${compatibility.aiMatchPercent}% ${l10n.discoverAiMatchLabel}',
      ));
    }

    if (compatibility.astroMatchPercent > 0) {
      badges.add(_GlassBadge(
        icon: Icons.auto_awesome_rounded,
        iconColor: AppColors.accentGoldLight,
        label: '${compatibility.astroMatchPercent}% ${l10n.discoverStatAstroLabel}',
      ));
    }

    if (compatibility.overallCompatibility > 0) {
      badges.add(_GlassBadge(
        icon: Icons.shield_rounded,
        iconColor: AppColors.faceVerificationGreen,
        label: '${compatibility.overallCompatibility} ${l10n.discoverStatTrustLabel}',
      ));
    }

    if (isVerified && badges.isEmpty) {
      badges.add(_GlassBadge(
        icon: Icons.task_alt_rounded,
        iconColor: AppColors.faceVerificationGreen,
        label: l10n.discoverVerifiedLabel.toUpperCase(),
      ));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: badges,
    );
  }
}

/// Frosted-glass pill used for score badges.
class _GlassBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;

  const _GlassBadge({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
