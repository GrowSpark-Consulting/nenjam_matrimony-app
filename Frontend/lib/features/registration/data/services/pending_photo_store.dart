import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/utils/photo_trace.dart';

/// Durable staging for photos picked during Create Account.
///
/// Onboarding's Add Photos step runs two screens before OTP mints a session,
/// so the photo has to survive until there is a credential to upload it with.
/// Holding a *path* was not enough: [PhotoCropScreen] hands back an
/// `XFile.fromData`, which on io is constructed as `File(path ?? '')` — so its
/// `path` is the empty string and the cropped image exists only as bytes in
/// memory. Queueing that path produced exactly the reported failure, a drain
/// reporting `missing=1` with nothing ever sent to the backend.
///
/// So the bytes are written to a real file first, under the app-support
/// directory rather than the cache directory: the OS reclaims caches whenever
/// it likes, and this has to outlive several screens and possibly a process
/// restart.
///
/// This is the one deliberate `dart:io` boundary in the onboarding photo
/// chain. Everything around it — the picker, the compressor, the drain, the
/// repository — stays on [XFile] so it runs unchanged on every platform, and
/// this is behind an interface so those parts can be tested without a disk.
abstract interface class PendingPhotoStore {
  /// Writes [photo]'s bytes to durable storage and returns the path to them.
  Future<String> stage(XFile photo);

  /// The staged file at [path], or null if it is gone or empty — in which
  /// case the member has to pick the photo again.
  Future<XFile?> read(String path);

  /// Deletes a staged file. Call only once the backend has the photo.
  Future<void> discard(String path);
}

/// Default [PendingPhotoStore], writing under the app-support directory.
class FilePendingPhotoStore implements PendingPhotoStore {
  const FilePendingPhotoStore();

  /// Subdirectory so staged photos can be reasoned about (and cleared) as a
  /// group, rather than being loose among whatever else lives in app support.
  static const _folder = 'pending_photos';

  @override
  Future<String> stage(XFile photo) async {
    final bytes = await photo.readAsBytes();
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/$_folder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // Microsecond stamp keeps two photos picked in the same second apart.
    final file = File(
      '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    // `flush: true` so the bytes are on disk before this returns — the
    // process can be killed between here and OTP.
    await file.writeAsBytes(bytes, flush: true);
    PhotoTrace.step('staged to durable storage', {
      'path': file.path,
      'bytes': bytes.length,
    });
    return file.path;
  }

  @override
  Future<XFile?> read(String path) async {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    // A zero-byte file would be rejected by the backend's own "Uploaded file
    // is empty" check, so treat it as lost rather than retry into a 400.
    if (await file.length() == 0) return null;
    return XFile(path);
  }

  @override
  Future<void> discard(String path) async {
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort. A staged file left behind costs a few hundred KB the OS
      // will reclaim with the app's data; failing the signup over it would
      // not.
    }
  }
}

final pendingPhotoStoreProvider = Provider<PendingPhotoStore>(
  (ref) => const FilePendingPhotoStore(),
);
