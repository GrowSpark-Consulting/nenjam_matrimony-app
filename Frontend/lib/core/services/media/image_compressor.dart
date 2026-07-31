import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Encodes raw cropped image bytes (PNG, straight off the crop screen's
/// [RenderRepaintBoundary] capture) down to a compressed JPEG and writes it
/// to a temp file ready for upload.
///
/// Pure-Dart (the `image` package), so the encode runs identically on every
/// platform this app targets — and, being CPU-bound, it's dispatched to a
/// background isolate via [compute] so a large photo never janks the crop
/// screen's "processing" animation.
abstract final class ImageCompressor {
  static Future<File> compressAndSave(
    Uint8List rawBytes, {
    int quality = 88,
  }) async {
    final jpegBytes = await compute(_encodeJpeg, _EncodeJob(rawBytes, quality));
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}${Platform.pathSeparator}crop_${DateTime.now().microsecondsSinceEpoch}.jpg';
    return File(path).writeAsBytes(jpegBytes, flush: true);
  }
}

class _EncodeJob {
  const _EncodeJob(this.bytes, this.quality);
  final Uint8List bytes;
  final int quality;
}

Uint8List _encodeJpeg(_EncodeJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) {
    throw StateError('ImageCompressor: could not decode cropped image bytes');
  }
  return img.encodeJpg(decoded, quality: job.quality);
}
