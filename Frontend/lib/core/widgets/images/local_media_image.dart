import 'package:flutter/widgets.dart';

import 'local_media_image_io.dart'
    if (dart.library.js_interop) 'local_media_image_web.dart';

/// Renders a locally-picked, not-yet-uploaded image on any platform.
///
/// The two platforms disagree about what "a local file" is, and that
/// disagreement is the whole reason this exists. On Android and iOS a picked
/// image is a path on disk, read by `FileImage`. In a browser there is no
/// path at all — `XFile.path` is a `blob:` object URL the browser resolves
/// from its own store, which `NetworkImage` fetches. The conditional import
/// above picks the right one at compile time, so `dart:io` never reaches the
/// web bundle.
///
/// [source] accepts either form; callers pass whatever `XFile.path` gave
/// them (or the equivalent value stored on a pending message) without
/// branching themselves.
class NmLocalMediaImage extends StatelessWidget {
  const NmLocalMediaImage({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.errorBuilder,
  });

  final String source;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Decode cap in physical pixels — the same concern as
  /// [NmSizedNetworkPhoto]: a 36 px reply thumbnail should not decode a
  /// multi-megapixel camera capture at full size.
  final int? cacheWidth;

  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ResizeImage.resizeIfNeeded(
        cacheWidth,
        null,
        localMediaImageProvider(source),
      ),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: errorBuilder,
    );
  }
}
