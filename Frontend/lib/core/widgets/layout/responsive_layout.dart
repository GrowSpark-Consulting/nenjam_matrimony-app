import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/responsive_utils.dart';

/// Constrains content width for larger screens (tablets/desktop).
class NmContentConstraint extends StatelessWidget {
  final Widget child;
  final double? maxWidth;

  const NmContentConstraint({super.key, required this.child, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final effectiveMaxWidth =
        maxWidth ?? ResponsiveUtils.maxContentWidth(context);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
        child: child,
      ),
    );
  }
}

/// Centers the whole app in a column no wider than
/// [ResponsiveUtils.appFrameMaxWidth] on tablets and desktops, and leaves
/// phones untouched.
///
/// Installed once, in `MaterialApp.builder`, so it bounds the Navigator and
/// therefore every route, dialog and bottom sheet. The [MediaQuery] below it
/// reports the framed width, so every existing breakpoint check
/// (`ResponsiveUtils.isDesktop`, grid column counts, ...) answers for the
/// space the app actually has rather than the browser window.
class NmAppFrame extends StatelessWidget {
  final Widget child;

  const NmAppFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final maxWidth = ResponsiveUtils.appFrameMaxWidth(context);
    if (maxWidth == double.infinity) return child;

    final media = MediaQuery.of(context);
    if (media.size.width <= maxWidth) return child;

    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: SizedBox(
          width: maxWidth,
          height: media.size.height,
          child: MediaQuery(
            data: media.copyWith(size: Size(maxWidth, media.size.height)),
            child: child,
          ),
        ),
      ),
    );
  }
}
