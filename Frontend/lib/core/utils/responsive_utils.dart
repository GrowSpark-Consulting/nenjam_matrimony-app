import 'package:flutter/material.dart';

import '../layout/window_class.dart';

/// Legacy responsive helpers, kept as a compatibility facade.
///
/// Superseded by `core/layout/window_class.dart` (classification) and
/// `core/layout/content_width.dart` (max-width tokens). The replacement
/// classifies from local `BoxConstraints`, so a surface in a narrow pane on a
/// wide monitor sees its pane rather than the window — which the
/// `MediaQuery`-based helpers here cannot do.
///
/// Existing call sites keep working unchanged; they migrate per surface. The
/// behavior below is pinned by `test/core/utils/responsive_utils_legacy_test.dart`
/// so it cannot drift mid-migration.
@Deprecated(
  'Use WindowClass (core/layout/window_class.dart) for classification and '
  'ContentWidth (core/layout/content_width.dart) for max widths. '
  'Classify from LayoutBuilder constraints, not MediaQuery.',
)
abstract final class ResponsiveUtils {
  // ─── Breakpoints ─────────────────────────────────────────────────
  static const double phoneSmall = 320;
  static const double phoneMedium = 375;
  static const double phoneLarge = 414;

  /// 600 — unchanged, and now the same number as
  /// [WindowClassBreakpoints.mediumMin].
  static const double tablet = WindowClassBreakpoints.mediumMin;

  /// 1024 — deliberately *not* [WindowClassBreakpoints.largeMin]. The legacy
  /// "desktop" threshold stays 1024 so existing callers are unaffected; the
  /// navigation rail's own threshold moves to 900 in the shell, which reads
  /// [WindowClass] directly rather than this value.
  static const double desktop = 1024;

  // ─── Device Type Detection ───────────────────────────────────────
  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < tablet) return DeviceType.phone;
    if (width < desktop) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  static bool isPhone(BuildContext context) =>
      getDeviceType(context) == DeviceType.phone;

  static bool isTablet(BuildContext context) =>
      getDeviceType(context) == DeviceType.tablet;

  static bool isDesktop(BuildContext context) =>
      getDeviceType(context) == DeviceType.desktop;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  // ─── Adaptive Values ─────────────────────────────────────────────
  /// Returns a value based on device type.
  static T adaptive<T>(
    BuildContext context, {
    required T phone,
    T? tablet,
    T? desktop,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return phone;
      case DeviceType.tablet:
        return tablet ?? phone;
      case DeviceType.desktop:
        return desktop ?? tablet ?? phone;
    }
  }

  // ─── Grid Columns ────────────────────────────────────────────────
  static int gridColumns(BuildContext context) =>
      adaptive(context, phone: 2, tablet: 3, desktop: 4);

  static int listColumns(BuildContext context) =>
      adaptive(context, phone: 1, tablet: 2, desktop: 3);

  // ─── Adaptive Padding ────────────────────────────────────────────
  static EdgeInsets pagePadding(BuildContext context) => EdgeInsets.symmetric(
    horizontal: adaptive(context, phone: 20.0, tablet: 32.0, desktop: 48.0),
    vertical: adaptive(context, phone: 16.0, tablet: 24.0, desktop: 32.0),
  );

  // ─── Max Content Width ───────────────────────────────────────────
  /// Constrains content width on larger screens (tablets/desktop)
  static double maxContentWidth(BuildContext context) =>
      adaptive(context, phone: double.infinity, tablet: 720.0, desktop: 960.0);

  // ─── Responsive Font Scale ───────────────────────────────────────
  static double fontScale(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= phoneSmall) return 0.85;
    if (width <= phoneMedium) return 0.92;
    if (width <= phoneLarge) return 1.0;
    if (width <= tablet) return 1.0;
    return 1.1;
  }

  // ─── Image Size Helpers ──────────────────────────────────────────
  static double profileImageSize(BuildContext context) =>
      adaptive(context, phone: 100.0, tablet: 120.0, desktop: 140.0);

  static double cardImageHeight(BuildContext context) =>
      adaptive(context, phone: 200.0, tablet: 240.0, desktop: 280.0);
}

/// Device type enum.
enum DeviceType { phone, tablet, desktop }
