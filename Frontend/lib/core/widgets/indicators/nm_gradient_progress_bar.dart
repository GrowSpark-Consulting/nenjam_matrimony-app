import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_gradients.dart';

/// Animated linear progress bar with a plum → magenta gradient fill.
///
/// `LinearProgressIndicator` can only paint a solid `valueColor`, so every
/// screen that wanted the brand ramp (drawer profile strength, profile
/// completeness hero, identity card) was falling back to a flat magenta.
/// This is that same bar with the gradient — one widget so the completion
/// visual reads identically everywhere it appears.
class NmGradientProgressBar extends StatelessWidget {
  /// 0.0–1.0 fill amount. Clamped, so callers can pass a raw ratio.
  final double value;

  /// Defaults to [AppGradients.progress] (plum → magenta).
  final Gradient gradient;

  /// Unfilled track. Defaults to the soft lavender surface.
  final Color? trackColor;

  final double height;
  final Duration duration;

  const NmGradientProgressBar({
    super.key,
    required this.value,
    this.gradient = AppGradients.progress,
    this.trackColor,
    this.height = 8,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track =
        trackColor ??
        (isDark
            ? AppColors.surfaceVariantDark
            : AppColors.primarySurfaceStrong);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: track,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                // A zero-width fill still needs to not render a stray
                // rounded nub, so the fraction is used directly rather than
                // clamped to a minimum.
                widthFactor: v,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: gradient),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
