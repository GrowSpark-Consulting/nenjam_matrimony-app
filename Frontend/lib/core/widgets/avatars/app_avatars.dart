import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../feedback/pulse_dot.dart';
import 'gender_placeholder.dart';

/// Reusable base Circle Avatar with CachedNetworkImage fallback.
class NmCircleAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final VoidCallback? onTap;

  /// 'Male' / 'Female' / '' — picks the fallback icon when [imageUrl] is
  /// null/empty.
  final String gender;

  /// Where [BoxFit.cover] anchors the crop — defaults to dead-center.
  /// Callers displaying a face-focused avatar (e.g. the nav drawer) can
  /// bias this slightly upward so the crop keeps the whole head in frame
  /// instead of centering on the torso.
  final Alignment alignment;

  const NmCircleAvatar({
    super.key,
    this.imageUrl,
    this.size = 48.0,
    this.onTap,
    this.gender = '',
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primarySurface,
        ),
        clipBehavior: Clip.antiAlias,
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? (imageUrl!.startsWith('assets/')
                  ? Image.asset(
                      imageUrl!,
                      fit: BoxFit.cover,
                      alignment: alignment,
                      errorBuilder: (_, __, ___) => _fallback(),
                    )
                  : CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      alignment: alignment,
                      // Avatars are 32–96 px; the source is a 1080² photo
                      // that would otherwise decode to ~4.6 MB apiece. The
                      // app bar avatar alone is on screen for the whole
                      // session.
                      memCacheWidth:
                          (size * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      errorWidget: (_, __, ___) => _fallback(),
                    ))
            : _fallback(),
      ),
    );
  }

  // Delegates to the single canonical gender-icon mapping in
  // [NmGenderPlaceholder] rather than duplicating the switch here — the
  // circular clip/background above is this widget's only real job.
  Widget _fallback() => NmGenderPlaceholder(
    gender: gender,
    iconSize: size * 0.6,
    backgroundColor: AppColors.primarySurface,
    iconColor: AppColors.primary,
  );
}

/// Online Avatar with green indicator badge.
class NmOnlineAvatar extends StatelessWidget {
  final String? imageUrl;
  final bool isOnline;
  final double size;
  final String gender;

  const NmOnlineAvatar({
    super.key,
    this.imageUrl,
    this.isOnline = true,
    this.size = 54.0,
    this.gender = '',
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NmCircleAvatar(imageUrl: imageUrl, size: size, gender: gender),
        if (isOnline)
          Positioned(
            right: 2,
            bottom: 2,
            child: NmPulseDot(
              size: size * 0.25,
              color: AppColors.online,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
      ],
    );
  }
}
