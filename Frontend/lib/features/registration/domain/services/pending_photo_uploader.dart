/// Drains the photos onboarding held back until a session existed.
///
/// Onboarding's Add Photos step runs before the member has a credential, so a
/// photo picked there is queued in [PhotoGallery] as a local path and uploaded
/// at the OTP step (see OnboardingVerifyMobilePage). This is that drain, kept
/// out of the widget so it can be tested without a Firebase session, an OTP,
/// or a running backend.
///
/// Deliberately depends on `package:cross_file` alone and NOT on `dart:io`.
/// The whole media chain — [AttachmentPicker], [ImageCompressor],
/// `PhotoRepository._multipart` — was made platform-neutral on purpose so the
/// same code serves Android, iOS and the web; a bare `File(path).exists()`
/// here would have made onboarding's photo step the one mobile-only link in
/// it. Reading and deleting staged files goes through [PendingPhotoStore],
/// which owns that one filesystem boundary.
library;

import 'package:cross_file/cross_file.dart';

import '../../data/services/pending_photo_store.dart';
import '../models/profile_draft.dart';

/// What one [drainPendingPhotos] pass did.
class PendingPhotoUploadResult {
  const PendingPhotoUploadResult({
    required this.uploaded,
    required this.failed,
    required this.missing,
    required this.remaining,
  });

  /// Photos the backend accepted. These are gone from [remaining].
  final int uploaded;

  /// Photos the upload rejected (network, 4xx, no session). Still in
  /// [remaining] so a later pass can retry them.
  final int failed;

  /// Queued entries whose local file is no longer readable — evicted from the
  /// cache directory, or lost with the process that wrote them. Dropped from
  /// [remaining], because retrying a file that does not exist can only fail
  /// again; the member has to pick the photo afresh.
  final int missing;

  /// The queue as it stands after this pass: everything that failed or was
  /// never reached, and nothing that succeeded or went missing.
  final PhotoGallery remaining;

  bool get hasFailures => failed > 0;
  bool get hasMissing => missing > 0;

  /// Whether anything at all needed doing — false for an empty queue, which
  /// is the ordinary case for a member who skipped the photo step.
  bool get didWork => uploaded > 0 || failed > 0 || missing > 0;
}

/// Uploads one queued file. Returns whether the backend accepted it.
///
/// `isPrimary` is true only for the entry occupying the gallery's primary
/// slot, so a retry of a non-primary photo can never displace an avatar that
/// already uploaded successfully.
typedef PendingPhotoUpload = Future<bool> Function(
  XFile file, {
  required bool isPrimary,
});

/// Uploads [gallery]'s queued photos in order, primary first.
///
/// Stops at the first upload failure rather than pressing on: the usual cause
/// is the session or the connection, which the next entry would hit too, and
/// stopping keeps the queue's order intact for the retry.
Future<PendingPhotoUploadResult> drainPendingPhotos({
  required PhotoGallery gallery,
  required PendingPhotoUpload upload,
  required PendingPhotoStore store,
}) async {
  final pending = gallery.pendingPaths;
  if (pending.isEmpty) {
    return PendingPhotoUploadResult(
      uploaded: 0,
      failed: 0,
      missing: 0,
      remaining: gallery,
    );
  }

  // Only index 0 is the primary slot, and only when one was actually set —
  // `pendingPaths` puts it first precisely so this holds.
  final hasPrimarySlot = gallery.primaryPhotoPath != null;
  String? retainedPrimary;
  final retainedGallery = <String>[];
  var uploaded = 0;
  var failed = 0;
  var missing = 0;

  void retain(String path, {required bool isPrimarySlot}) {
    if (isPrimarySlot) {
      retainedPrimary = path;
    } else {
      retainedGallery.add(path);
    }
  }

  for (var i = 0; i < pending.length; i++) {
    final path = pending[i];
    final isPrimarySlot = hasPrimarySlot && i == 0;

    final file = await store.read(path);
    if (file == null) {
      missing++;
      continue;
    }

    bool accepted;
    try {
      accepted = await upload(file, isPrimary: isPrimarySlot);
    } catch (_) {
      // An uploader that throws is a failed upload, not a lost photo — keep
      // the entry so it can be retried.
      accepted = false;
    }

    if (accepted) {
      uploaded++;
      // Only now — the staged copy is the sole record of this photo until the
      // backend has it, so deleting any earlier would turn a failed upload
      // into a lost photo.
      await store.discard(path);
      continue;
    }

    failed++;
    retain(path, isPrimarySlot: isPrimarySlot);
    // Everything after this was never attempted; it stays queued too. None of
    // these can be the primary slot, which is index 0 and already handled.
    for (var j = i + 1; j < pending.length; j++) {
      retain(pending[j], isPrimarySlot: false);
    }
    break;
  }

  return PendingPhotoUploadResult(
    uploaded: uploaded,
    failed: failed,
    missing: missing,
    remaining: PhotoGallery(
      primaryPhotoPath: retainedPrimary,
      galleryPaths: retainedGallery,
    ),
  );
}
