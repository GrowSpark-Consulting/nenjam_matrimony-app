import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../theme/app_colors.dart';

/// Shimmer loading placeholder.
class NmShimmer extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Widget? child;

  const NmShimmer({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
    this.child,
  });

  /// Circular shimmer for avatars.
  const NmShimmer.circle({
    super.key,
    required double size,
  })  : width = size,
        height = size,
        borderRadius = 999,
        child = null;

  /// Card shimmer placeholder.
  const NmShimmer.card({
    super.key,
  })  : width = double.infinity,
        height = 200,
        borderRadius = 20,
        child = null;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: isDark
          ? AppColors.shimmerBaseDark
          : AppColors.shimmerBaseLight,
      highlightColor: isDark
          ? AppColors.shimmerHighlightDark
          : AppColors.shimmerHighlightLight,
      child: child ??
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
          ),
    );
  }
}

/// Pre-built shimmer for profile card list.
class NmShimmerProfileCard extends StatelessWidget {
  const NmShimmerProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NmShimmer(height: 200, borderRadius: 20),
        SizedBox(height: 12),
        NmShimmer(width: 140, height: 16),
        SizedBox(height: 8),
        NmShimmer(width: 100, height: 12),
      ],
    );
  }
}
