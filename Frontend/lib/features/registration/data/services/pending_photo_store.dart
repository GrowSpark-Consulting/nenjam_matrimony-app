import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

/// Web [PendingPhotoStore]. A browser has no app-support directory —
/// `getApplicationSupportDirectory` has no web implementation and `File` is
/// unavailable — so the photo stays where `XFile.fromData` already put it: in
/// the page's memory, addressed by a `blob:` object URL that lives until the
/// tab is closed or reloaded.
///
/// That is enough for every in-app step between the photo screen and OTP (all
/// of them are route changes inside the same page). It is *not* durable across
/// a reload or a closed tab; [read] then returns null and the member picks the
/// photo again — the same outcome the mobile store gives for a lost file, so
/// the uploader's `missing` handling covers it.
class BlobPendingPhotoStore implements PendingPhotoStore {
  const BlobPendingPhotoStore();

  @override
  Future<String> stage(XFile photo) async {
    final path = photo.path;
    // Reading it back now proves the blob really holds bytes before the
    // caller records the path as the only copy.
    if (path.isEmpty || await photo.length() == 0) {
      throw StateError('The selected photo has no data.');
    }
    return path;
  }

  @override
  Future<XFile?> read(String path) async {
    if (path.isEmpty) return null;
    try {
      final file = XFile(path);
      return await file.length() == 0 ? null : file;
    } catch (_) {
      // A revoked or expired blob URL — the page was reloaded since staging.
      return null;
    }
  }

  @override
  Future<void> discard(String path) async {
    // Nothing on disk to delete; the browser frees the blob with the page.
  }
}

final pendingPhotoStoreProvider = Provider<PendingPhotoStore>(
  (ref) =>
      kIsWeb ? const BlobPendingPhotoStore() : const FilePendingPhotoStore(),
);
