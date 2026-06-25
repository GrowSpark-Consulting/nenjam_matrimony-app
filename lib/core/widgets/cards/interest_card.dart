import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';
import '../buttons/outlined_button.dart';
import '../buttons/primary_button.dart';

/// Interest card for sent / received matrimonial express interest notifications.
class NmInterestCard extends StatelessWidget {
  final String name;
  final String details;
  final String message;
  final String? imageUrl;
  final bool isReceived;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const NmInterestCard({
    super.key,
    required this.name,
    required this.details,
    required this.message,
    this.imageUrl,
    this.isReceived = true,
    this.onAccept,
    this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
                backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
                child: imageUrl == null ? const Icon(Icons.favorite, color: AppColors.liked) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTypography.titleMedium),
                    Text(details, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondaryLight)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isReceived ? AppColors.successLight : AppColors.infoLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isReceived ? 'Received' : 'Sent',
                  style: AppTypography.labelSmall.copyWith(
                    color: isReceived ? AppColors.success : AppColors.info,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '"$message"',
                style: AppTypography.bodyMedium.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ],
          if (isReceived && onAccept != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: NmOutlinedButton(
                    label: 'Decline',
                    onPressed: onDecline,
                    height: 44,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NmPrimaryButton(
                    label: 'Accept',
                    onPressed: onAccept,
                    height: 44,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
