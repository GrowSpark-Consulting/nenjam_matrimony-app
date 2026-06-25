import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';
import '../buttons/primary_button.dart';

/// Visitor card displaying profile visit log and action button.
class NmVisitorCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final String timeAgo;
  final String? imageUrl;
  final VoidCallback? onConnect;
  final VoidCallback? onTap;

  const NmVisitorCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.timeAgo,
    this.imageUrl,
    this.onConnect,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppDecorations.card(isDark: isDark),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
              backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
              child: imageUrl == null ? const Icon(Icons.person, size: 28, color: AppColors.textSecondaryLight) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(name, style: AppTypography.titleMedium),
                      Text(timeAgo, style: AppTypography.labelSmall.copyWith(color: AppColors.textTertiaryLight)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondaryLight), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (onConnect != null) ...[
              const SizedBox(width: 12),
              NmPrimaryButton(
                label: 'Connect',
                onPressed: onConnect,
                width: 100,
                height: 40,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
