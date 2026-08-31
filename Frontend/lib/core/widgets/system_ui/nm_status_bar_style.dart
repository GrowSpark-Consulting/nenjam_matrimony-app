import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Single source of truth for status-bar icon brightness.
///
/// Every full-bleed/no-AppBar page used to pick its own
/// `SystemUiOverlayStyle.light`/`.dark` literal (or, worse, picked none at
/// all and silently inherited whatever the previous screen — or the current
/// [ThemeData]'s `AppBarTheme` — left behind). That let a page's status-bar
/// icons drift out of sync with its actual background: Discover's Scaffold
/// is hardcoded to a light background in every theme mode, but relied on
/// `AppBarTheme.systemOverlayStyle`, which flips to light (white) icons in
/// dark mode — invisible against Discover's still-light background.
///
/// [styleFor] derives the correct icon brightness directly from the color
/// actually painted behind the status bar, so it can never disagree with
/// what the page looks like. Pages that render entirely through `AppBar`/
/// `AppBarTheme` (Premium, Chat, Notifications, ...) don't need this — their
/// AppBar's background and its `systemOverlayStyle` both come from the same
/// theme object and can't drift apart. This is only for screens that draw
/// their own background outside that mechanism.
abstract final class NmStatusBarStyle {
  /// The status-bar style that keeps icons legible over [background].
  static SystemUiOverlayStyle styleFor(Color background) {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
  }
}

/// Wraps [child] in an [AnnotatedRegion] set to [NmStatusBarStyle.styleFor]
/// of [background] — the color painted directly behind the status bar,
/// typically the page's own `Scaffold.backgroundColor` or the color at the
/// top of a full-bleed gradient/photo.
class NmPageStatusBar extends StatelessWidget {
  final Color background;
  final Widget child;

  const NmPageStatusBar({
    super.key,
    required this.background,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: NmStatusBarStyle.styleFor(background),
      child: child,
    );
  }
}
