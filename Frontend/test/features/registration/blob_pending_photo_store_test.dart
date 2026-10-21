import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/registration/data/services/pending_photo_store.dart';

/// The web store never touches the filesystem itself — it hands the picked
/// photo's own handle back. These tests use a temp file as the stand-in for a
/// `blob:` URL, since `XFile(path)` reads either the same way.
void main() {
  const store = BlobPendingPhotoStore();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('blob_store_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File photo(List<int> bytes) =>
      File('${dir.path}/p.jpg')..writeAsBytesSync(bytes);

  test(
    'stage returns the photo path and read gives the same bytes back',
    () async {
      final f = photo([1, 2, 3]);
      final path = await store.stage(XFile(f.path));
      expect(path, f.path);

      final back = await store.read(path);
      expect(await back!.readAsBytes(), [1, 2, 3]);
    },
  );

  test('an empty photo is refused at staging, not queued', () async {
    final f = photo([]);
    expect(() => store.stage(XFile(f.path)), throwsStateError);
  });

  test('a photo that has since vanished reads back as missing', () async {
    final f = photo([9]);
    final path = await store.stage(XFile(f.path));
    f.deleteSync();
    expect(await store.read(path), isNull);
    expect(await store.read(''), isNull);
  });

  test('discard is a harmless no-op', () async {
    await store.discard('blob:http://x/abc');
    await store.discard('');
  });
}
