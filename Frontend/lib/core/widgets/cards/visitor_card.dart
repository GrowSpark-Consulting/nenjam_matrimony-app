import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';
import '../avatars/app_avatars.dart';
import '../buttons/primary_button.dart';

/// Visitor card displaying profile visit log and action button.
class NmVisitorCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final String timeAgo;
  final String? imageUrl;
  /// 'Male' / 'Female' / '' — picks the gender-aware placeholder icon
  /// when [imageUrl] is null.
  final String gender;
  final VoidCallback? onConnect;
  final VoidCallback? onTap;

  const NmVisitorCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.timeAgo,
    this.imageUrl,
    this.gender = '',
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
            NmCircleAvatar(imageUrl: imageUrl, size: 56, gender: gender),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // A real visitor name is unbounded-length user
                      // content — Expanded+ellipsis keeps timeAgo visible
                      // instead of letting the Row overflow horizontally.
                      Expanded(
                        child: Text(
                          name,
                          style: AppTypography.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(timeAgo,
                          style: AppTypography.labelSmall
                              .copyWith(color: AppColors.textTertiaryLight)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondaryLight), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (onConnect != null) ...[
              const SizedBox(width: 12),
              // width:100 only comfortably fit "Connect" at 1.0x scale;
              // 128 gives headroom for larger text-scale settings, with
              // NmPrimaryButton's label falling back to ellipsis beyond that.
              NmPrimaryButton(
                label: 'Connect',
                onPressed: onConnect,
                width: 128,
                height: 40,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
