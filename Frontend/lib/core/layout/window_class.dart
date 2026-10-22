import 'package:flutter/widgets.dart';

/// Width thresholds for [WindowClass], as half-open intervals.
abstract final class WindowClassBreakpoints {
  /// Smallest width that counts as [WindowClass.medium].
  static const double mediumMin = 600;

  /// Smallest width that counts as [WindowClass.expanded].
  static const double expandedMin = 900;

  /// Smallest width that counts as [WindowClass.large].
  static const double largeMin = 1200;
}

/// How much horizontal room a piece of UI has to work with.
///
/// Deliberately describes *available space*, not a device: the same phone in
/// landscape, a tablet, a resized browser window and a 400px detail pane on a
/// 1920px monitor are classified by what they actually offer. That is why
/// surfaces must classify from their own [BoxConstraints] via [fromWidth]
/// rather than from the window via [of] — see the class docs on [of].
enum WindowClass {
  /// Below 600: phones in portrait, narrow panes, small embedded web views.
  compact,

  /// 600–899: large phones in landscape, small tablets, half-screen windows.
  medium,

  /// 900–1199: tablets in landscape, small laptop windows.
  expanded,

  /// 1200 and above: desktop browsers and larger.
  large;

  /// Classifies a raw width. Intervals are half-open, so 599 is [compact] and
  /// 600 is [medium].
  ///
  /// Tolerates `double.infinity` (an unbounded constraint, treated as [large])
  /// and negative widths (treated as [compact]) so a caller inside an
  /// unbounded or degenerate layout never throws.
  static WindowClass fromWidth(double width) {
    if (width >= WindowClassBreakpoints.largeMin) return large;
    if (width >= WindowClassBreakpoints.expandedMin) return expanded;
    if (width >= WindowClassBreakpoints.mediumMin) return medium;
    return compact;
  }

  /// Classifies the whole window.
  ///
  /// **Use this only for shell-level decisions** — which navigation affordance
  /// to show. For anything laid out *inside* the shell, wrap the surface in a
  /// `LayoutBuilder` and use [fromWidth] with the local constraints instead:
  /// a surface in a narrow pane on a wide monitor must see its pane, not the
  /// monitor.
  static WindowClass of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == compact;
  bool get isMedium => this == medium;
  bool get isExpanded => this == expanded;
  bool get isLarge => this == large;

  /// True for [medium] and wider — i.e. not a narrow phone-width surface.
  bool get isAtLeastMedium => index >= medium.index;

  /// True for [expanded] and wider — the threshold at which the navigation
  /// rail replaces the bottom pill and two-pane layouts become available.
  bool get isAtLeastExpanded => index >= expanded.index;

  /// Picks the value for this class, falling back down the chain when a tier
  /// is omitted: [large] tries large → expanded → medium → compact.
  T resolve<T>({required T compact, T? medium, T? expanded, T? large}) {
    switch (this) {
      case WindowClass.compact:
        return compact;
      case WindowClass.medium:
        return medium ?? compact;
      case WindowClass.expanded:
        return expanded ?? medium ?? compact;
      case WindowClass.large:
        return large ?? expanded ?? medium ?? compact;
    }
  }
}
