import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/media/attachment_picker.dart';
import '../../../../core/services/media/crop_service.dart';
import '../../../../core/services/media/photo_crop_screen.dart' show CropShape;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/repositories/photo_repository.dart';
import '../../domain/models/user_photo.dart';
import '../providers/photo_providers.dart';
import '../../../../l10n/app_localizations.dart';

const int kMaxPhotos = 6;

/// Self-contained profile-photo manager: fetches the user's photos, lets them
/// add (camera/gallery), set primary, replace, delete, and drag-to-reorder —
/// all wired to the backend PhotoController via [myPhotosProvider]. Reused by
/// the registration wizard's photo step and the edit-profile flow, so the two
/// stay in lockstep automatically (same provider).
class PhotoManagerSection extends ConsumerStatefulWidget {
  const PhotoManagerSection({super.key});

  @override
  ConsumerState<PhotoManagerSection> createState() =>
      _PhotoManagerSectionState();
}

class _PhotoManagerSectionState extends ConsumerState<PhotoManagerSection> {
  final _attachmentPicker = AttachmentPicker();
  final _cropService = const CropService();

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(myPhotosProvider);
    final photos = photosAsync.valueOrNull ?? const <UserPhoto>[];
    final busy = photosAsync.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppLocalizations.of(context).photosYourPhotos,
                style: AppTypography.labelLarge,
              ),
            ),
            Text(
              '${photos.length}/$kMaxPhotos',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        photosAsync.when(
          // Only a full-screen spinner when there's no prior data to show;
          // during mutations the previous list stays visible with an overlay.
          loading: () => photos.isEmpty
              ? const _LoadingState()
              : _buildGallery(context, photos, busy: true),
          error: (error, _) => _ErrorState(
            message: error is PhotoApiException
                ? error.message
                : AppLocalizations.of(context).photosLoadError,
            onRetry: () => ref.read(myPhotosProvider.notifier).refresh(),
          ),
          data: (list) => list.isEmpty
              ? _EmptyState(onAdd: _onAddTap)
              : _buildGallery(context, list, busy: busy),
        ),
      ],
    );
  }

  Widget _buildGallery(
    BuildContext context,
    List<UserPhoto> photos, {
    required bool busy,
  }) {
    final canAddMore = photos.length < kMaxPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 160,
          child: Stack(
            children: [
              ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                itemCount: photos.length,
                onReorderItem: (oldIndex, newIndex) =>
                    _onReorder(photos, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(photo.id),
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _PhotoTile(
                        photo: photo,
                        onTap: () => _showPhotoOptions(photo),
                      ),
                    ),
                  );
                },
              ),
              if (busy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.photoScrimSoft,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (canAddMore)
          OutlinedButton.icon(
            onPressed: busy ? null : _onAddTap,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text(AppLocalizations.of(context).registrationAddPhoto),
          ),
        const SizedBox(height: 6),
        Text(
          AppLocalizations.of(context).photosReorderHint,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiaryLight,
          ),
        ),
      ],
    );
  }

  Future<void> _onReorder(
    List<UserPhoto> photos,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) return;
    // `onReorderItem` already accounts for the dragged item being removed at
    // oldIndex, so newIndex is the final slot — no manual shift needed.
    final reordered = [...photos];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    await _run(
      () => ref
          .read(myPhotosProvider.notifier)
          .reorder(reordered.map((p) => p.id).toList()),
    );
  }

  void _onAddTap() => _pickAndUpload(makePrimaryIfFirst: true);

  Future<void> _pickAndUpload({
    bool makePrimaryIfFirst = false,
    String? replaceId,
    bool replacingPrimary = false,
  }) async {
    final source = await _chooseSource();
    if (source == null || !mounted) return;

    // Fetch a generously high-res source — the crop screen now owns final
    // downscale/compression post-crop (see CropService/ImageCompressor), so
    // downscaling this early would soften the image if the user zooms in.
    final file = await _attachmentPicker.pick(
      context,
      source,
      maxWidth: 2048,
      imageQuality: 95,
    );
    if (file == null || !mounted) return; // cancelled, denied, or failed

    final currentCount = ref.read(myPhotosProvider).valueOrNull?.length ?? 0;
    final willBePrimary = replaceId != null
        ? replacingPrimary
        : (makePrimaryIfFirst && currentCount == 0);

    final cropped = await _cropService.pickAndCrop(
      context: context,
      sourceFile: file,
      shape: willBePrimary ? CropShape.circle : CropShape.square,
    );
    if (cropped == null || !mounted) return; // cancelled crop

    // The uncropped source is no longer explicitly deleted. It is an XFile
    // now, which has no cross-platform delete: on web there is no file to
    // remove (the bytes are released when the reference goes out of scope),
    // and on mobile `image_picker` writes into the OS cache directory, which
    // Android and iOS reclaim on their own. Only `cropped` is retained past
    // this point, so the larger source buffer becomes collectable here.

    final notifier = ref.read(myPhotosProvider.notifier);

    await _run(() async {
      if (replaceId != null) {
        await notifier.replace(replaceId, cropped);
      } else {
        await notifier.upload(cropped, isPrimary: willBePrimary ? true : null);
      }
    });
  }

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppColors.primary,
              ),
              title: Text(AppLocalizations.of(context).inboxChooseFromGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_rounded,
                color: AppColors.secondary,
              ),
              title: Text(AppLocalizations.of(context).inboxTakePhoto),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showPhotoOptions(UserPhoto photo) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            if (!photo.isPrimary)
              ListTile(
                leading: const Icon(
                  Icons.star_rounded,
                  color: AppColors.secondary,
                ),
                title: Text(AppLocalizations.of(context).photosSetAsDisplay),
                onTap: () {
                  Navigator.pop(ctx);
                  _run(
                    () => ref
                        .read(myPhotosProvider.notifier)
                        .setPrimary(photo.id),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.sync_rounded, color: AppColors.primary),
              title: Text(AppLocalizations.of(context).photosReplace),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload(
                  replaceId: photo.id,
                  replacingPrimary: photo.isPrimary,
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: Text(AppLocalizations.of(context).photosDelete),
              onTap: () {
                Navigator.pop(ctx);
                _run(
                  () => ref.read(myPhotosProvider.notifier).delete(photo.id),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Runs a mutation and surfaces its backend error (if any) as a snackbar —
  /// the provider already flips to an error state, this just makes it visible
  /// for one-shot actions.
  Future<void> _run(Future<void> Function() action) async {
    await action();
    if (!mounted) return;
    final state = ref.read(myPhotosProvider);
    state.whenOrNull(
      error: (error, _) => _snack(
        error is PhotoApiException
            ? error.message
            : AppLocalizations.of(context).authGenericError,
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.onTap,
  });

  final UserPhoto photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: photo.cdnUrl,
              width: 116,
              height: 160,
              fit: BoxFit.cover,
              // Grid thumbnails, not full photos — decode to the tile's
              // longest edge rather than the source 1080².
              memCacheWidth: (160 * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              placeholder: (_, __) => Container(
                width: 116,
                height: 160,
                color: AppColors.surfaceVariantLight,
              ),
              errorWidget: (_, __, ___) => Container(
                width: 116,
                height: 160,
                color: AppColors.surfaceVariantLight,
                child: const Icon(Icons.broken_image_outlined, size: 28),
              ),
            ),
          ),
          if (photo.isPrimary)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'DISPLAY',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
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

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 160,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 2,
          ),
          color: AppColors.surfaceVariantLight,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_a_photo_rounded,
              size: 44,
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context).photosAddFirst,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.error.withValues(alpha: 0.06),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.error, size: 32),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(AppLocalizations.of(context).commonRetry),
          ),
        ],
      ),
    );
  }
}
