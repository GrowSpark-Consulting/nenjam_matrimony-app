import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/widgets/images/sized_network_photo.dart';
import '../../../../core/layout/mouse_drag_scroll.dart';

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
    final canAddMore = photoUrls.length < maxPhotos;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl2),
        boxShadow: [
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
                  AppLocalizations.of(context).photosGalleryTitle,
                  style: AppTypography.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canAddMore)
                Semantics(
                  label: AppLocalizations.of(context).registrationAddPhoto,
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
            child: NmMouseDragScroll(
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
                        child: _PhotoThumbnail(url: entry.value),
                      ),
                    ),
                  ),

                  // Add placeholder
                  if (canAddMore)
                    GestureDetector(
                      onTap: onAddTap,
                      child: const _AddThumbnail(),
                    ),
                ],
              ),
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

  const _PhotoThumbnail({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: SizedBox(
        width: 108,
        height: 148,
        child: url.startsWith('assets/')
            ? Image.asset(url, fit: BoxFit.cover)
            : NmSizedNetworkPhoto(
                url: url,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.surfaceVariantLight,
                  child: const Icon(Icons.broken_image_outlined, size: 32),
                ),
              ),
      ),
    );
  }
}

/// Dashed "ADD" placeholder tile.
class _AddThumbnail extends StatelessWidget {
  const _AddThumbnail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 108,
      height: 148,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.borderLight,
          width: 1.5,
          // Using a workaround — Flutter doesn't natively support dashed borders
          // without a package. We simulate it with opacity + solid thin border.
        ),
        color: AppColors.surfaceVariantLight,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.add_photo_alternate_outlined,
            size: 28,
            color: AppColors.textTertiaryLight,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'ADD',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textTertiaryLight,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
