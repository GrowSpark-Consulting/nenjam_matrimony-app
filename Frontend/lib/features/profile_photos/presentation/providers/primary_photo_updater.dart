import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/media/attachment_picker.dart';
import '../../../../core/services/media/crop_service.dart';
import '../../../../core/services/media/photo_crop_screen.dart';
import '../../../../core/utils/photo_trace.dart';
import '../../data/repositories/photo_repository.dart';
import 'photo_providers.dart';

/// Outcome of [PrimaryPhotoUpdater.pickAndUpload].
enum PrimaryPhotoUpdateStatus {
  /// A new primary photo was uploaded and the photo providers refreshed.
  success,

  /// The member backed out (source sheet dismissed, picker cancelled, crop
  /// cancelled) — not an error, so callers show nothing.
  cancelled,

  /// The upload was attempted and failed; [PrimaryPhotoUpdateResult.message]
  /// carries the backend's own wording where it supplied one.
  failure,
}

class PrimaryPhotoUpdateResult {
  const PrimaryPhotoUpdateResult(this.status, {this.message});

  const PrimaryPhotoUpdateResult.success()
    : status = PrimaryPhotoUpdateStatus.success,
      message = null;

  const PrimaryPhotoUpdateResult.cancelled()
    : status = PrimaryPhotoUpdateStatus.cancelled,
      message = null;

  final PrimaryPhotoUpdateStatus status;

  /// Backend-supplied failure text, when there was one. Callers fall back to
  /// their own localized generic string when this is null.
  final String? message;

  bool get isSuccess => status == PrimaryPhotoUpdateStatus.success;
  bool get isFailure => status == PrimaryPhotoUpdateStatus.failure;
}

/// Picks an image and uploads it as the member's **primary** photo, reusing
/// the same pipeline the profile/onboarding photo manager uses:
/// [AttachmentPicker] → [CropService] (which also compresses) →
/// [PhotosController.upload], which carries the Firebase token, refetches the
/// authoritative list and invalidates the profile cache.
///
/// Extracted so a caller outside the photo manager — the Face Verification
/// mismatch card — can offer "update my main photo" without navigating into
/// registration/onboarding, and without a second upload implementation.
///
/// Primary-photo replacement is the backend's job: `POST /profiles/me/photos`
/// with `isPrimary=true` demotes the existing primary in the same transaction
/// that inserts the new row (see PhotoRepository.create), so this never
/// creates a second primary and needs no follow-up `setPrimary` call.
class PrimaryPhotoUpdater {
  const PrimaryPhotoUpdater(this._ref);

  final Ref _ref;

  /// Runs the pick → crop/compress → upload-as-primary sequence.
  ///
  /// [chooseSource] lets the caller present its own source sheet; the default
  /// goes straight to the gallery, which is what the mismatch card wants.
  Future<PrimaryPhotoUpdateResult> pickAndUpload({
    required BuildContext context,
    ImageSource source = ImageSource.gallery,
    AttachmentPicker? picker,
    CropService cropService = const CropService(),
  }) async {
    final attachmentPicker = picker ?? AttachmentPicker();
    PhotoTrace.begin('primary photo update source=${source.name}');
    try {
      // Same generous source resolution the photo manager requests — the crop
      // screen owns the final downscale/compression, so fetching small here
      // would soften a zoomed crop.
      final file = await attachmentPicker.pick(
        context,
        source,
        maxWidth: 2048,
        imageQuality: 95,
      );
      if (file == null) {
        PhotoTrace.step('picker returned null (cancelled/denied/failed)');
        return const PrimaryPhotoUpdateResult.cancelled();
      }
      if (!context.mounted) {
        return const PrimaryPhotoUpdateResult.cancelled();
      }

      // Circle guide: this image is becoming the display photo.
      final cropped = await cropService.pickAndCrop(
        context: context,
        sourceFile: file,
        shape: CropShape.circle,
      );
      if (cropped == null) {
        PhotoTrace.step('crop cancelled');
        return const PrimaryPhotoUpdateResult.cancelled();
      }

      final notifier = _ref.read(myPhotosProvider.notifier);
      await notifier.upload(cropped, isPrimary: true);

      // PhotosController.upload publishes its outcome into myPhotosProvider
      // (and already refetched the list on success) rather than throwing.
      final state = _ref.read(myPhotosProvider);
      final error = state.error;
      if (error != null) {
        return PrimaryPhotoUpdateResult(
          PrimaryPhotoUpdateStatus.failure,
          message: error is PhotoApiException ? error.message : null,
        );
      }
      return const PrimaryPhotoUpdateResult.success();
    } finally {
      PhotoTrace.end('primary photo update');
    }
  }
}

final primaryPhotoUpdaterProvider = Provider<PrimaryPhotoUpdater>(
  PrimaryPhotoUpdater.new,
);

/// Whether an in-place primary-photo update (pick → crop → upload) is running.
///
/// Spans the whole operation, including the pick/crop legs that happen before
/// any network call — [myPhotosProvider] only goes loading once the upload
/// itself starts, which is too late to gate a concurrent action on.
class PrimaryPhotoUpdateInProgress extends Notifier<bool> {
  @override
  bool build() => false;

  void set({required bool running}) => state = running;
}

final primaryPhotoUpdateInProgressProvider =
    NotifierProvider<PrimaryPhotoUpdateInProgress, bool>(
      PrimaryPhotoUpdateInProgress.new,
    );
