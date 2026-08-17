import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Encodes raw cropped image bytes (PNG, straight off the crop screen's
/// [RenderRepaintBoundary] capture) down to a compressed JPEG.
///
/// Pure-Dart (the `image` package) and byte-in/byte-out, so it runs
/// identically on Android, iOS and the web. It deliberately does **not**
/// touch the filesystem: web has no `dart:io` filesystem, and the only
/// consumer needs bytes for a multipart upload anyway, so writing a temp
/// file was an extra round trip that also made the whole media chain
/// mobile-only.
///
/// The encode is CPU-bound so it is dispatched through [compute]. On Android
/// and iOS that is a real background isolate and the crop screen's
/// "processing" spinner animates normally. The web has no isolates, so
/// `compute` runs inline on the main thread there and the spinner will hold
/// still for the duration of the encode — a one-off cost on confirm, not
/// something in a scroll or gesture path.
abstract final class ImageCompressor {
  /// Returns JPEG bytes ready to hand to `MultipartFile.fromBytes`.
  static Future<Uint8List> compressToJpeg(
    Uint8List rawBytes, {
    int quality = 88,
  }) {
    return compute(_encodeJpeg, _EncodeJob(rawBytes, quality));
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
