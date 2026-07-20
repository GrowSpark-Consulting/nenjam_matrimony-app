import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Photo Gallery card — horizontal scroll of photo thumbnails with an
/// add-photo dashed placeholder at the end.
class NmPhotoGalleryCard extends StatelessWidget {
  final List<String> photoUrls;
  final int maxPhotos;
  final VoidCallback? onAddTap;
  final void Function(int index)? onPhotoTap;

  const NmPhotoGalleryCard({
    super.key,
    this.photoUrls = const [],
    this.maxPhotos = 6,
    this.onAddTap,
    this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canAddMore = photoUrls.length < maxPhotos;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl2),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  'Photo Gallery',
                  style: AppTypography.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canAddMore)
                Semantics(
                  label: 'Add photo',
                  button: true,
                  child: GestureDetector(
                    onTap: onAddTap,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Horizontal scroll
          SizedBox(
            height: 148,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                // Existing photos
                ...photoUrls.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: GestureDetector(
                      onTap: onPhotoTap == null ? null : () => onPhotoTap!(entry.key),
                      child: _PhotoThumbnail(url: entry.value, isDark: isDark),
                    ),
                  ),
                ),

                // Add placeholder
                if (canAddMore)
                  GestureDetector(
                    onTap: onAddTap,
                    child: _AddThumbnail(isDark: isDark),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single photo thumbnail.
class _PhotoThumbnail extends StatelessWidget {
  final String url;
  final bool isDark;

  const _PhotoThumbnail({required this.url, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: SizedBox(
        width: 108,
        height: 148,
        child: url.startsWith('assets/')
            ? Image.asset(url, fit: BoxFit.cover)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: isDark
                      ? AppColors.surfaceVariantDark
                      : AppColors.surfaceVariantLight,
                  child: const Icon(Icons.broken_image_outlined, size: 32),
                ),
              ),
      ),
    );
  }
}

/// Dashed "ADD" placeholder tile.
class _AddThumbnail extends StatelessWidget {
  final bool isDark;
  const _AddThumbnail({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 108,
      height: 148,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1.5,
          // Using a workaround — Flutter doesn't natively support dashed borders
          // without a package. We simulate it with opacity + solid thin border.
        ),
        color: isDark
            ? AppColors.surfaceVariantDark.withValues(alpha: 0.5)
            : AppColors.surfaceVariantLight,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 28,
            color: isDark
                ? AppColors.textTertiaryDark
                : AppColors.textTertiaryLight,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'ADD',
            style: AppTypography.labelSmall.copyWith(
              color: isDark
                  ? AppColors.textTertiaryDark
                  : AppColors.textTertiaryLight,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
