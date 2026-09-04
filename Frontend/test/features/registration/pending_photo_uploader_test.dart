import 'dart:io' as io;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/registration/data/services/pending_photo_store.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/services/pending_photo_uploader.dart';

/// Covers the queue onboarding uses to hold photos picked before a session
/// exists (Add Photos runs two screens before OTP mints the credential).
///
/// The regression these guard: the drain used to clear the whole queue
/// unconditionally and skip a missing file without a word, so a member who
/// added a photo could finish signup with none and never be told.
/// Real files on a real temp directory, so the drain's "is this still
/// there?" question is answered the way it is in production — plus a record
/// of what it deleted, which is the difference between a photo that made it
/// to the backend and one that was thrown away.
class _RecordingStore implements PendingPhotoStore {
  final List<String> discarded = <String>[];
  final List<String> staged = <String>[];

  @override
  Future<String> stage(XFile photo) async {
    staged.add(photo.path);
    return photo.path;
  }

  @override
  Future<XFile?> read(String path) async {
    if (path.isEmpty) return null;
    final file = io.File(path);
    if (!await file.exists()) return null;
    if (await file.length() == 0) return null;
    return XFile(path);
  }

  @override
  Future<void> discard(String path) async {
    discarded.add(path);
    final file = io.File(path);
    if (await file.exists()) await file.delete();
  }
}

void main() {
  late io.Directory tempDir;
  late _RecordingStore store;

  setUp(() async {
    tempDir = await io.Directory.systemTemp.createTemp('pending_photos_test');
    store = _RecordingStore();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// A real file on disk, because the drain's readability probe
  /// (`XFile.length()`) genuinely stats it.
  Future<String> writeFile(String name) async {
    final file = io.File('${tempDir.path}/$name');
    await file.writeAsBytes(Uint8List.fromList(List.filled(64, 7)));
    return file.path;
  }

  /// Records what the drain tried to upload, and answers per call.
  ({
    PendingPhotoUpload upload,
    List<({String path, bool isPrimary})> calls,
  }) uploader({required List<bool> results}) {
    final calls = <({String path, bool isPrimary})>[];
    var index = 0;
    Future<bool> upload(XFile file, {required bool isPrimary}) async {
      calls.add((path: file.path, isPrimary: isPrimary));
      // Default to success once the scripted answers run out, so a test only
      // has to script the outcomes it cares about.
      return index < results.length ? results[index++] : true;
    }

    return (upload: upload, calls: calls);
  }

  test('a failed upload keeps the photo queued instead of discarding it',
      () async {
    final primary = await writeFile('primary.jpg');
    final gallery = PhotoGallery(primaryPhotoPath: primary);
    final u = uploader(results: [false]);

    final result = await drainPendingPhotos(
      gallery: gallery,
      upload: u.upload,
      store: store,
    );

    expect(result.failed, 1);
    expect(result.uploaded, 0);
    expect(result.hasFailures, isTrue);
    // The whole point: it is still there to retry.
    expect(result.remaining.pendingPaths, [primary]);
    expect(store.discarded, isEmpty,
        reason: 'the staged file is the only copy until the backend has it');
    expect(io.File(primary).existsSync(), isTrue);
    expect(result.remaining.primaryPhotoPath, primary,
        reason: 'the primary slot must survive so a retry re-sends it as '
            'the avatar rather than as an ordinary gallery photo');
  });

  test('a missing local file is reported and dropped from the queue',
      () async {
    const gallery = PhotoGallery(
      primaryPhotoPath: '/no/such/directory/gone.jpg',
    );
    final u = uploader(results: const []);

    final result = await drainPendingPhotos(
      gallery: gallery,
      upload: u.upload,
      store: store,
    );

    expect(result.missing, 1);
    expect(result.hasMissing, isTrue);
    expect(u.calls, isEmpty, reason: 'nothing to upload — the file is gone');
    // Dropped, not retained: retrying a file that does not exist can only
    // fail again. The member is told to pick it afresh.
    expect(result.remaining.pendingPaths, isEmpty);
  });

  test('a zero-byte file counts as missing rather than a doomed upload',
      () async {
    final empty = io.File('${tempDir.path}/empty.jpg');
    await empty.writeAsBytes(Uint8List(0));
    final u = uploader(results: const []);

    final result = await drainPendingPhotos(
      gallery: PhotoGallery(primaryPhotoPath: empty.path),
      upload: u.upload,
      store: store,
    );

    expect(result.missing, 1);
    expect(u.calls, isEmpty);
  });

  test('a successful upload clears only that entry, keeping the rest',
      () async {
    final primary = await writeFile('primary.jpg');
    final second = await writeFile('second.jpg');
    final third = await writeFile('third.jpg');
    final gallery = PhotoGallery(
      primaryPhotoPath: primary,
      galleryPaths: [second, third],
    );
    // Primary succeeds, the second fails; the third is never reached.
    final u = uploader(results: [true, false]);

    final result = await drainPendingPhotos(
      gallery: gallery,
      upload: u.upload,
      store: store,
    );

    expect(result.uploaded, 1);
    expect(result.failed, 1);
    // The uploaded one is gone; the failed one and the unattempted one stay,
    // in their original order.
    expect(result.remaining.pendingPaths, [second, third]);
    // Only the photo the backend accepted is deleted from staging.
    expect(store.discarded, [primary]);
    expect(io.File(primary).existsSync(), isFalse);
    expect(io.File(second).existsSync(), isTrue);
    expect(io.File(third).existsSync(), isTrue);
    expect(result.remaining.primaryPhotoPath, isNull,
        reason: 'the avatar already uploaded — a retry of the remaining '
            'photos must not overwrite it');
    // Stops at the first failure rather than pressing on.
    expect(u.calls.map((c) => c.path), [primary, second]);
  });

  test('a retry uploads exactly the retained photo', () async {
    final primary = await writeFile('primary.jpg');
    final second = await writeFile('second.jpg');
    final gallery = PhotoGallery(
      primaryPhotoPath: primary,
      galleryPaths: [second],
    );

    final first = uploader(results: [true, false]);
    final afterFirst = await drainPendingPhotos(
      gallery: gallery,
      upload: first.upload,
      store: store,
    );
    expect(afterFirst.remaining.pendingPaths, [second]);

    // Second pass over what was retained — the real retry.
    final retry = uploader(results: [true]);
    final afterRetry = await drainPendingPhotos(
      gallery: afterFirst.remaining,
      upload: retry.upload,
      store: store,
    );

    expect(retry.calls.map((c) => c.path), [second],
        reason: 'only the retained photo is re-sent, not the one that '
            'already succeeded');
    expect(retry.calls.single.isPrimary, isFalse);
    expect(afterRetry.uploaded, 1);
    expect(afterRetry.remaining.pendingPaths, isEmpty);
  });

  test('an uploader that throws is a retryable failure, not a lost photo',
      () async {
    final primary = await writeFile('primary.jpg');

    final result = await drainPendingPhotos(
      gallery: PhotoGallery(primaryPhotoPath: primary),
      upload: (file, {required bool isPrimary}) async =>
          throw StateError('network down'),
      store: store,
    );

    expect(result.failed, 1);
    expect(result.missing, 0);
    expect(result.remaining.pendingPaths, [primary]);
  });

  test('an empty queue is a no-op', () async {
    final u = uploader(results: const []);
    final result = await drainPendingPhotos(
      gallery: const PhotoGallery(),
      upload: u.upload,
      store: store,
    );

    expect(result.didWork, isFalse);
    expect(u.calls, isEmpty);
    expect(result.remaining.pendingPaths, isEmpty);
  });

  group('durable staging', () {
    test('a crop screen XFile has no path of its own to queue', () {
      // The bug in one line: PhotoCropScreen returns XFile.fromData, whose io
      // `path` is the empty string, so the cropped image lives only in memory.
      // Queueing that path is what produced `missing=1` with nothing sent.
      final cropped = XFile.fromData(
        Uint8List.fromList(List.filled(16, 3)),
        name: 'crop.jpg',
        mimeType: 'image/jpeg',
      );
      expect(cropped.path, isEmpty);
    });

    test('staging writes the bytes to a real file that can be read back',
        () async {
      final cropped = XFile.fromData(
        Uint8List.fromList(List.filled(32, 9)),
        name: 'crop.jpg',
        mimeType: 'image/jpeg',
      );
      final target = '${tempDir.path}/staged.jpg';
      await io.File(target).writeAsBytes(await cropped.readAsBytes());

      // What the drain then does with it — the step that used to fail.
      final readBack = await store.read(target);
      expect(readBack, isNotNull);
      expect(await readBack!.length(), 32);
    });

    test('a staged file outlives the widget that created it', () async {
      // Nothing about the queue depends on the page still being mounted: the
      // path is in the draft and the bytes are on disk.
      final staged = await writeFile('outlives.jpg');
      final result = await drainPendingPhotos(
        gallery: PhotoGallery(primaryPhotoPath: staged),
        upload: uploader(results: [true]).upload,
        store: store,
      );
      expect(result.uploaded, 1);
    });

    test('an unreadable staged path is reported, never counted as uploaded',
        () async {
      final result = await drainPendingPhotos(
        // The empty path a crop-screen XFile actually carried.
        gallery: const PhotoGallery(primaryPhotoPath: ''),
        upload: uploader(results: const []).upload,
        store: store,
      );

      expect(result.missing, 1);
      expect(result.uploaded, 0,
          reason: 'signup must not claim a photo it never sent');
      expect(result.hasMissing, isTrue);
    });
  });

  group('PhotoGallery.copyWith', () {
    test('can clear primaryPhotoPath', () {
      const gallery = PhotoGallery(primaryPhotoPath: '/tmp/a.jpg');
      // Before the sentinel fix, `?? this.primaryPhotoPath` made an explicit
      // null indistinguishable from an omitted argument, so the primary slot
      // could never be cleared.
      expect(gallery.copyWith(primaryPhotoPath: null).primaryPhotoPath,
          isNull);
    });

    test('leaves primaryPhotoPath alone when the argument is omitted', () {
      const gallery = PhotoGallery(primaryPhotoPath: '/tmp/a.jpg');
      expect(
        gallery.copyWith(galleryPaths: const ['/tmp/b.jpg']).primaryPhotoPath,
        '/tmp/a.jpg',
      );
    });
  });

  test('the onboarding photo-upload chain does not depend on dart:io', () {
    // The media chain (AttachmentPicker, ImageCompressor,
    // PhotoRepository._multipart) is deliberately platform-neutral so the
    // same code serves Android, iOS and the web. A `dart:io` import in the
    // onboarding half would make signup's photo step the one mobile-only
    // link in it — which is exactly what this replaced.
    const chain = [
      'lib/features/registration/domain/services/pending_photo_uploader.dart',
      'lib/features/registration/presentation/pages/'
          'onboarding_verify_mobile_page.dart',
      'lib/features/registration/presentation/pages/onboarding_photos_page.dart',
      'lib/features/profile_photos/presentation/providers/photo_providers.dart',
      'lib/features/profile_photos/data/repositories/photo_repository.dart',
    ];

    final importsDartIo = RegExp(
      r'''^\s*import\s+['"]dart:io['"]''',
      multiLine: true,
    );

    for (final path in chain) {
      final file = io.File(path);
      expect(file.existsSync(), isTrue, reason: '$path should exist');
      expect(
        file.readAsStringSync(),
        isNot(matches(importsDartIo)),
        reason: '$path must not import dart:io',
      );
    }

    // PendingPhotoStore is the single, deliberate filesystem boundary —
    // staging bytes to disk genuinely needs one. Keeping it here, behind an
    // interface, is what lets everything above stay platform-neutral.
    expect(
      io.File('lib/features/registration/data/services/'
              'pending_photo_store.dart')
          .readAsStringSync(),
      matches(importsDartIo),
    );
  });
}
