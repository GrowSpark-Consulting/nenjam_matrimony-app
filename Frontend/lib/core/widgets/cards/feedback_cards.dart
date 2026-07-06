import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';
import '../buttons/primary_button.dart';

/// Reusable Verification Prompt Card.
class NmVerificationCard extends StatelessWidget {
  final VoidCallback? onVerify;
  const NmVerificationCard({super.key, this.onVerify});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.verifiedBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded, size: 36, color: AppColors.verifiedBlue),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Get Verified Badge', style: AppTypography.titleMedium.copyWith(color: AppColors.verifiedBlue)),
                Text('Profiles with verified ID get 3x more match responses.', style: AppTypography.bodySmall),
              ],
            ),
          ),
          if (onVerify != null) ...[
            const SizedBox(width: 12),
            NmPrimaryButton(label: 'Verify', onPressed: onVerify, width: 80, height: 36),
          ],
        ],
      ),
    );
  }
}

/// Reusable Notification Card.
class NmNotificationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String time;
  final IconData icon;
  final bool isUnread;

  const NmNotificationCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.time,
    this.icon = Icons.notifications_rounded,
    this.isUnread = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card(isDark: isDark).copyWith(
        color: isUnread ? (isDark ? AppColors.surfaceVariantDark : AppColors.infoLight.withValues(alpha: 0.5)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 20, backgroundColor: AppColors.primarySurface, child: Icon(icon, size: 20, color: AppColors.primary)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleSmall.copyWith(fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(time, style: AppTypography.labelSmall.copyWith(color: AppColors.textTertiaryLight)),
        ],
      ),
    );
  }
}

/// Reusable Success Alert Card.
class NmSuccessCard extends StatelessWidget {
  final String message;
  const NmSuccessCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: AppTypography.bodyMedium.copyWith(color: AppColors.success, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

/// Reusable Information Card.
class NmInformationCard extends StatelessWidget {
  final String message;
  const NmInformationCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.infoLight, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.info_rounded, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: AppTypography.bodyMedium.copyWith(color: AppColors.info, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

/// Reusable Warning Alert Card.
class NmWarningCard extends StatelessWidget {
  final String message;
  const NmWarningCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.warningLight, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: AppTypography.bodyMedium.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
