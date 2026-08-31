import 'package:flutter/material.dart';

import '../../theme/app_typography.dart';

/// Animated circular score/percent gauge shared by every "ring with a
/// number in the middle" visual in the app (Profile Performance's
/// Strength/Visibility/Response gauges) — extracted so each
/// screen stops hand-rolling its own near-identical
/// `TweenAnimationBuilder<double>` + `CircularProgressIndicator` pair.
class NmScoreRing extends StatelessWidget {
  /// 0.0–1.0 fill amount.
  final double value;
  final String displayText;
  final Color color;

  /// Defaults to a faint tint of [color] when unset.
  final Color? backgroundColor;
  final Color? textColor;
  final double size;
  final double strokeWidth;
  final double fontSize;
  final FontWeight fontWeight;
  final Duration duration;

  const NmScoreRing({
    super.key,
    required this.value,
    required this.displayText,
    required this.color,
    this.backgroundColor,
    this.textColor,
    this.size = 68,
    this.strokeWidth = 5,
    this.fontSize = 20,
    this.fontWeight = FontWeight.w800,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CircularProgressIndicator(
              value: v,
              strokeWidth: strokeWidth,
              strokeCap: StrokeCap.round,
              backgroundColor:
                  backgroundColor ??
                  color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          // The value is also conveyed by the ring's progress, so this
          // compact label is exempted from system font scaling — a
          // fixed-diameter ring has no room to grow into at large
          // accessibility text sizes.
          MediaQuery.withNoTextScaling(
            child: Text(
              displayText,
              style: AppTypography.titleLarge.copyWith(
                color: textColor,
                fontWeight: fontWeight,
                fontSize: fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
