import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/images/sized_network_photo.dart';
import '../../../../l10n/app_localizations.dart';
import 'profile_photo_viewer_page.dart';

/// The viewed member's *other* uploaded photos, as a 1-large + up-to-4-small
/// mosaic.
///
/// Deliberately not `NmPhotoGalleryCard`: that card is the owner-facing
/// horizontal strip with an "add photo" affordance, which is wrong on both
/// counts here (read-only, and the target layout is a mosaic). The pieces it
/// is built from — the card decoration, [NmSizedNetworkPhoto], and
/// [ProfilePhotoViewerPage] for the full-screen tap target — are reused
/// unchanged.
///
/// [photoUrls] is expected to already exclude the hero photo; indices map
/// straight onto it, so tapping tile *n* opens the viewer at *n*.
class ProfilePhotoGallerySection extends StatelessWidget {
  /// Additional photos only — the main/hero photo is not part of this list.
  final List<String> photoUrls;

  const ProfilePhotoGallerySection({super.key, required this.photoUrls});

  /// How many tiles the mosaic itself renders: one large plus at most four
  /// small. Anything beyond that is surfaced as a "+N" overlay on the last
  /// tile rather than a taller grid.
  static const int _maxTiles = 5;

  void _openViewer(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePhotoViewerPage(
          photoUrls: photoUrls,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPaddingLarge,
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.photosGalleryTitle, style: AppTypography.titleLarge),
          const SizedBox(height: AppSpacing.base),
          if (photoUrls.isEmpty)
            _EmptyGallery(
              message: l10n.profileDetailNoMorePhotos,
            )
          else
            ..._mosaic(context),
        ],
      ),
    );
  }

  /// The large tile, then the row of up to three small tiles, then the wide
  /// closing tile — each part only rendered when there are photos to fill it,
  /// so 1, 2, 3, 4, and 5+ photos all lay out without gaps or placeholders.
  List<Widget> _mosaic(BuildContext context) {
    final visible = photoUrls.take(_maxTiles).toList();
    final overflowCount = photoUrls.length - visible.length;

    Widget tile(int index, {int badgeCount = 0}) => _GalleryTile(
      url: visible[index],
      overflowCount: badgeCount,
      onTap: () => _openViewer(context, index),
    );

    final rowTiles = visible.skip(1).take(3).toList();
    final hasWideTile = visible.length >= 5;

    return [
      AspectRatio(
        aspectRatio: 4 / 3,
        child: tile(0, badgeCount: visible.length == 1 ? overflowCount : 0),
      ),
      if (rowTiles.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        // No IntrinsicHeight and deliberately no CrossAxisAlignment.stretch:
        // this Row sits in a Column inside a scroll view, so its own height is
        // unbounded and stretching would hand each child h=Infinity. Left at
        // the default, every child is an AspectRatio inside an Expanded, so
        // the row's height falls out of the shared tile width instead — which
        // keeps the squares square on a 320px phone and a tablet alike.
        Row(
          children: [
            for (var i = 0; i < rowTiles.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: tile(
                    i + 1,
                    badgeCount: (!hasWideTile && i == rowTiles.length - 1)
                        ? overflowCount
                        : 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
      if (hasWideTile) ...[
        const SizedBox(height: AppSpacing.sm),
        AspectRatio(
          aspectRatio: 5 / 2,
          child: tile(4, badgeCount: overflowCount),
        ),
      ],
    ];
  }
}

class _GalleryTile extends StatelessWidget {
  final String url;
  final VoidCallback onTap;

  /// When > 0, dims the tile and stacks a "+N" label over it — the photos
  /// that exist but did not get their own tile are still reachable by tapping
  /// through to the viewer.
  final int overflowCount;

  const _GalleryTile({
    required this.url,
    required this.onTap,
    this.overflowCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    const placeholderColor = AppColors.surfaceVariantLight;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          url.startsWith('assets/')
              ? Image.asset(url, fit: BoxFit.cover)
              : NmSizedNetworkPhoto(
                  url: url,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: placeholderColor,
                    child: Icon(Icons.broken_image_outlined, size: 28),
                  ),
                ),
          if (overflowCount > 0)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(
                child: Text(
                  '+$overflowCount',
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap),
          ),
        ],
      ),
    );
  }
}

/// "No other photos" state — the same warm surface tile the rest of the
/// design system uses for empty slots, deliberately not shaped like a photo
/// so it can't read as one.
class _EmptyGallery extends StatelessWidget {
  final String message;

  const _EmptyGallery({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: 28,
            color: AppColors.textTertiaryLight,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
