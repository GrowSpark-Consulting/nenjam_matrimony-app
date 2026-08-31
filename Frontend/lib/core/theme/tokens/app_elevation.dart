import 'package:flutter/material.dart';

import '../app_shadows.dart';

/// Nenjam Matrimony — Elevation Tokens
///
/// Flat, Low, Medium, High, Floating.
abstract final class AppElevation {
  static const double flat = 0.0;
  static const double low = 2.0;
  static const double medium = 4.0;
  static const double high = 8.0;
  static const double floating = 16.0;

  /// Returns corresponding luxury soft shadows based on elevation token.
  static List<BoxShadow> shadow(double elevation) {
    if (elevation == flat) return const [];
    if (elevation <= low) {
      return AppShadows.cardLight;
    }
    if (elevation <= medium) {
      return AppShadows.floatingLight;
    }
    return AppShadows.glowAccent;
  }
}
