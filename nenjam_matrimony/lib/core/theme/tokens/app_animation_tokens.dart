import 'package:flutter/material.dart';

/// Nenjam Matrimony — Animation Tokens
///
/// Subtle and premium luxury micro-animation durations and curves.
abstract final class AppAnimationTokens {
  // Durations
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration pageTransition = Duration(milliseconds: 400);

  // Curves
  static const Curve luxuryCurve = Cubic(0.2, 0.0, 0.0, 1.0); // Emphasized Decelerate
  static const Curve buttonPressCurve = Curves.easeOutCubic;
  static const Curve cardHoverCurve = Curves.easeInOutQuart;
}
