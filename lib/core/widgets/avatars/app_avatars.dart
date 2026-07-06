import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_gradients.dart';

/// Reusable base Circle Avatar with CachedNetworkImage fallback.
class NmCircleAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final VoidCallback? onTap;

  const NmCircleAvatar({
    super.key,
    this.imageUrl,
    this.size = 48.0,
    this.onTap,
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
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Center(child: Icon(Icons.person_rounded, size: size * 0.6, color: AppColors.primary));
}

/// Profile Avatar.
class NmProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  const NmProfileAvatar({super.key, this.imageUrl, this.size = 100.0});

  @override
  Widget build(BuildContext context) => NmCircleAvatar(imageUrl: imageUrl, size: size);
}

/// Online Avatar with green indicator badge.
class NmOnlineAvatar extends StatelessWidget {
  final String? imageUrl;
  final bool isOnline;
  final double size;

  const NmOnlineAvatar({super.key, this.imageUrl, this.isOnline = true, this.size = 54.0});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NmCircleAvatar(imageUrl: imageUrl, size: size),
        if (isOnline)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: size * 0.25,
              height: size * 0.25,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
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

  const NmVerifiedAvatar({super.key, this.imageUrl, this.size = 54.0});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NmCircleAvatar(imageUrl: imageUrl, size: size),
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

  const NmPremiumAvatar({super.key, this.imageUrl, this.size = 54.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppGradients.goldButton,
      ),
      child: NmCircleAvatar(imageUrl: imageUrl, size: size - 5),
    );
  }
}

/// Story Avatar with animated luxury gradient ring.
class NmStoryAvatar extends StatelessWidget {
  final String? imageUrl;
  final bool hasStory;
  final double size;
  final VoidCallback? onTap;

  const NmStoryAvatar({
    super.key,
    this.imageUrl,
    this.hasStory = true,
    this.size = 64.0,
    this.onTap,
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
          child: NmCircleAvatar(imageUrl: imageUrl, size: size - 10),
        ),
      ),
    );
  }
}
