import 'package:flutter/material.dart';

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