import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_gradients.dart';
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
        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primarySurface),
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

/// Profile Avatar.
class NmProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final String gender;
  const NmProfileAvatar({super.key, this.imageUrl, this.size = 100.0, this.gender = ''});

  @override
  Widget build(BuildContext context) =>
      NmCircleAvatar(imageUrl: imageUrl, size: size, gender: gender);
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

/// Verified Avatar with blue checkmark badge.
class NmVerifiedAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final String gender;

  const NmVerifiedAvatar({super.key, this.imageUrl, this.size = 54.0, this.gender = ''});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NmCircleAvatar(imageUrl: imageUrl, size: size, gender: gender),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.verified_rounded, size: 16, color: AppColors.verifiedBlue),
          ),
        ),
      ],
    );
  }
}

/// Premium Avatar with gold border glow.
class NmPremiumAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final String gender;

  const NmPremiumAvatar({super.key, this.imageUrl, this.size = 54.0, this.gender = ''});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppGradients.goldButton,
      ),
      child: NmCircleAvatar(imageUrl: imageUrl, size: size - 5, gender: gender),
    );
  }
}

/// Story Avatar with animated luxury gradient ring.
class NmStoryAvatar extends StatelessWidget {
  final String? imageUrl;
  final bool hasStory;
  final double size;
  final VoidCallback? onTap;
  final String gender;

  const NmStoryAvatar({
    super.key,
    this.imageUrl,
    this.hasStory = true,
    this.size = 64.0,
    this.onTap,
    this.gender = '',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: hasStory ? AppGradients.goldButton : null,
          border: hasStory ? null : Border.all(color: AppColors.borderLight),
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
          child: NmCircleAvatar(imageUrl: imageUrl, size: size - 10, gender: gender),
        ),
      ),
    );
  }
}
