import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The upload pipeline standardises every profile photo at 1080×1080 JPEG
/// (see `PhotoCropScreen.outputSize`), so asking the decoder for more than
/// this buys nothing — it would just re-encode the same pixels larger.
const int _sourcePhotoMaxPixels = 1080;

/// An [Image.network] that decodes at roughly the size it is actually drawn
/// at, rather than at the source photo's full resolution.
///
/// Every profile photo in the app is a 1080×1080 JPEG. Flutter decodes to
/// uncompressed ARGB, so without a `cacheWidth` each one occupies
/// 1080 × 1080 × 4 ≈ 4.6 MB in [PaintingBinding.imageCache] — the same 4.6 MB
/// whether it is filling the screen or sitting in a 76 px story ring. A feed
/// that renders a dozen photos therefore blows past the cache's default
/// 100 MB ceiling and starts evicting and re-decoding mid-scroll.
///
/// The correct decode size is a layout property, not something a call site
/// can hardcode: it depends on the widget's constraints *and* the device
/// pixel ratio. So this reads the real constraints via [LayoutBuilder] and
/// derives `cacheWidth` from them, which means every caller gets the right
/// size on every screen size and density without passing anything.
///
/// Deliberately still [Image.network] and not `CachedNetworkImage`: profile
/// photo URLs are short-lived **presigned** GETs against a private bucket
/// (see `UserPhoto.cdnUrl`), so they must not be persisted to disk, and a
/// URL-keyed disk cache would never hit anyway because the signature changes
/// on every fetch. This widget addresses decode cost only; download cost
/// needs stable URLs from the backend first.
class NmSizedNetworkPhoto extends StatelessWidget {
  const NmSizedNetworkPhoto({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Image.network(
          url,
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          cacheWidth: _decodeWidth(constraints, devicePixelRatio),
          errorBuilder: errorBuilder,
          loadingBuilder: loadingBuilder,
        );
      },
    );
  }

  /// Physical pixels to decode to, or null to leave the image uncapped.
  ///
  /// Sizes from the **larger** edge rather than the width: the source is
  /// square and [BoxFit.cover] scales it until it covers the longer side, so
  /// sizing by width alone would visibly under-decode any box taller than it
  /// is wide (the full-height feed cards, the Matches reel).
  int? _decodeWidth(BoxConstraints constraints, double devicePixelRatio) {
    final longestEdge = math.max(constraints.maxWidth, constraints.maxHeight);
    // An unbounded parent gives no size to work from — decode uncapped
    // rather than guess, so this can never make an image blurry.
    if (!longestEdge.isFinite || longestEdge <= 0) return null;

    final physical = (longestEdge * devicePixelRatio).round();
    return math.min(physical, _sourcePhotoMaxPixels);
  }
}
