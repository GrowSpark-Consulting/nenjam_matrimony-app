import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';

/// Reusable luxury floating action button supporting standard & extended modes.
class NmFloatingActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String? label;
  final bool isGold;

  const NmFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.label,
    this.isGold = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isGold ? AppColors.accentGold : AppColors.primary;
    final fg = isGold ? AppColors.textOnGold : Colors.white;

    if (label != null) {
      return Container(
        decoration: BoxDecoration(boxShadow: AppShadows.floatingLight),
        child: FloatingActionButton.extended(
          onPressed: onPressed,
          backgroundColor: bg,
          foregroundColor: fg,
          icon: Icon(icon),
          label: Text(label!, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: AppShadows.floatingLight),
      child: FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: bg,
        foregroundColor: fg,
        child: Icon(icon),
      ),
    );
  }
}
