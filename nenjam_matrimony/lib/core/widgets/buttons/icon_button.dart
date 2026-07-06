import 'package:flutter/material.dart';

import '../../theme/tokens/app_touch_target.dart';

/// Accessible icon button enforcing 48dp minimum touch target.
class NmIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  const NmIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: AppTouchTarget.minConstraints,
      child: IconButton(
        icon: Icon(icon, size: size),
        onPressed: onPressed,
        tooltip: tooltip,
        color: color,
        splashRadius: 24,
      ),
    );
  }
}
