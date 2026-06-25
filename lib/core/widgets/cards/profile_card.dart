import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';
import '../badges/premium_badge.dart';
import '../badges/verification_badge.dart';

/// Premium profile card — used in search, matches, and discovery.
class NmProfileCard extends StatelessWidget {
  final String name;
  final String age;
  final String location;
  final String? imageUrl;
  final String? profession;
  final bool isVerified;
  final bool isPremium;
  final bool isOnline;
  final VoidCallback? onTap;
  final VoidCallback? onLikeTap;
  final VoidCallback? onShortlistTap;

  const NmProfileCard({
    super.key,
    required this.name,
    required this.age,
    required this.location,
    this.imageUrl,
    this.profession,
    this.isVerified = false,
    this.isPremium = false,
    this.isOnline = false,
    this.onTap,
    this.onLikeTap,
    this.onShortlistTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: AppDecorations.card(isDark: isDark),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Image
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image placeholder
                  Container(
                    color: isDark
                        ? AppColors.surfaceVariantDark
                        : AppColors.surfaceVariantLight,
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildPlaceholder(isDark),
                          )
                        : _buildPlaceholder(isDark),
                  ),

                  // Gradient overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: AppDecorations.imageOverlay,
                    ),
                  ),

                  // Online indicator
                  if (isOnline)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.online,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),

                  // Badges
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Row(
                      children: [
                        if (isPremium) ...[
                          const NmPremiumBadge(size: NmBadgeSize.small),
                          const SizedBox(width: 6),
                        ],
                        if (isVerified)
                          const NmVerificationBadge(
                            size: NmBadgeSize.small,
                          ),
                      ],
                    ),
                  ),

                  // Bottom info overlay
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$name, $age',
                          style: AppTypography.titleMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          location,
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      profession ?? '',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onShortlistTap != null)
                    _ActionIcon(
                      icon: Icons.bookmark_border_rounded,
                      onTap: onShortlistTap!,
                      tooltip: 'Shortlist',
                    ),
                  if (onLikeTap != null) ...[
                    const SizedBox(width: 4),
                    _ActionIcon(
                      icon: Icons.favorite_border_rounded,
                      onTap: onLikeTap!,
                      color: AppColors.liked,
                      tooltip: 'Like',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) => Center(
        child: Icon(
          Icons.person_rounded,
          size: 48,
          color: isDark
              ? AppColors.textTertiaryDark
              : AppColors.textTertiaryLight,
        ),
      );
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final String tooltip;

  const _ActionIcon({
    required this.icon,
    required this.onTap,
    this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}
