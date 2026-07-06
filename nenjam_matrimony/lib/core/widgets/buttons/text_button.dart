import 'package:flutter/material.dart';

import '../../theme/app_typography.dart';

/// Reusable text button supporting loading, icons, and disabled states.
class NmTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color? color;

  const NmTextButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: TextButton(
        onPressed: isLoading ? null : onPressed,
        style: color != null
            ? TextButton.styleFrom(foregroundColor: color)
            : null,
        child: isLoading
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color ?? Theme.of(context).colorScheme.primary,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 6),
                  ],
                  Text(label, style: AppTypography.button),
                ],
              ),
      ),
    );
  }
}
