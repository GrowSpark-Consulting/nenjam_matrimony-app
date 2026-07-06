import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../buttons/primary_button.dart';

/// Linear Loader.
class NmLinearLoader extends StatelessWidget {
  final double? value;
  const NmLinearLoader({super.key, this.value});

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: value,
      backgroundColor: AppColors.primarySurface,
      color: AppColors.accentGold,
      minHeight: 4,
    );
  }
}

/// Skeleton Loader block.
class NmSkeletonLoader extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const NmSkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.radius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? AppColors.shimmerBaseDark : AppColors.shimmerBaseLight,
      highlightColor: isDark ? AppColors.shimmerHighlightDark : AppColors.shimmerHighlightLight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
      ),
    );
  }
}

/// Image Placeholder box.
class NmImagePlaceholder extends StatelessWidget {
  final double size;
  const NmImagePlaceholder({super.key, this.size = 64.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.surfaceVariantLight, borderRadius: BorderRadius.circular(12)),
      child: const Center(child: Icon(Icons.image_outlined, color: AppColors.textTertiaryLight)),
    );
  }
}

/// Retry Widget.
class NmRetryWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const NmRetryWidget({
    super.key,
    this.message = 'Something went wrong. Please try again.',
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, size: 48, color: AppColors.textSecondaryLight),
            const SizedBox(height: 16),
            Text(message, style: AppTypography.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            NmPrimaryButton(label: 'Retry', onPressed: onRetry, width: 140, height: 44),
          ],
        ),
      ),
    );
  }
}

/// No Internet Widget.
class NmNoInternetWidget extends StatelessWidget {
  final VoidCallback onRetry;
  const NmNoInternetWidget({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 64, color: AppColors.warning),
            const SizedBox(height: 20),
            Text('No Internet Connection', style: AppTypography.titleLarge),
            const SizedBox(height: 8),
            Text('Please check your network settings and try reconnecting.', style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondaryLight), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            NmPrimaryButton(label: 'Reconnect', onPressed: onRetry, width: 160),
          ],
        ),
      ),
    );
  }
}

/// Server Error Widget.
class NmServerErrorWidget extends StatelessWidget {
  final VoidCallback onRetry;
  const NmServerErrorWidget({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 20),
            Text('Server Error (500)', style: AppTypography.titleLarge),
            const SizedBox(height: 8),
            Text('Our matrimonial servers are currently undergoing maintenance or experiencing issues.', style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondaryLight), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            NmPrimaryButton(label: 'Try Again', onPressed: onRetry, width: 160),
          ],
        ),
      ),
    );
  }
}
