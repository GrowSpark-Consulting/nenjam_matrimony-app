import 'package:flutter/material.dart';

import '../../theme/app_typography.dart';

/// Outlined border button.
class NmOutlinedButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double height;

  const NmOutlinedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: OutlinedButton(
        // See NmPrimaryButton's matching comment — the app-wide
        // OutlinedButtonTheme hardcodes 32dp of vertical padding sized for
        // this widget's own 56dp default, which clips the label at smaller
        // custom [height]s (e.g. the Accept/Decline/Withdraw buttons at
        // 44dp). Overriding padding/minimumSize/tapTargetSize here makes
        // this SizedBox's [height] the actual authority on total size.
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  // Flexible + ellipsis so a squeezed button (narrow
                  // Expanded flex share, long localized label, or large
                  // text-scale settings) truncates gracefully instead of
                  // throwing a RenderFlex overflow.
                  Flexible(
                    child: Text(
                      label,
                      style: AppTypography.button,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
