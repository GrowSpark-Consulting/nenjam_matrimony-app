import 'package:flutter/material.dart';

import '../../utils/responsive_utils.dart';

/// Responsive layout builder that renders different layouts
/// based on device type (phone, tablet, desktop).
class NmResponsiveLayout extends StatelessWidget {
  final Widget phone;
  final Widget? tablet;
  final Widget? desktop;

  const NmResponsiveLayout({
    super.key,
    required this.phone,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final deviceType = ResponsiveUtils.getDeviceType(context);

        switch (deviceType) {
          case DeviceType.desktop:
            return desktop ?? tablet ?? phone;
          case DeviceType.tablet:
            return tablet ?? phone;
          case DeviceType.phone:
            return phone;
        }
      },
    );
  }
}

/// Constrains content width for larger screens (tablets/desktop).
class NmContentConstraint extends StatelessWidget {
  final Widget child;
  final double? maxWidth;

  const NmContentConstraint({
    super.key,
    required this.child,
    this.maxWidth,
  });

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
