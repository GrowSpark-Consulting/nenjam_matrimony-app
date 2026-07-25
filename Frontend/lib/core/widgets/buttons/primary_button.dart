import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Primary filled button with full-width layout.
class NmPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double height;

  const NmPrimaryButton({
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
      child: ElevatedButton(
        // The app-wide ElevatedButtonTheme (app_theme.dart) hardcodes
        // `padding: vertical 16` (32dp total) + `minimumSize.height: 56`,
        // sized for this widget's own 56dp default. At a smaller custom
        // [height] (e.g. 44dp, used by Accept/Decline/Withdraw), that fixed
        // 32dp padding left less than the label's own line-height worth of
        // room inside the tightly-constrained SizedBox, clipping the text —
        // not a font-size problem, a padding/height mismatch. Overriding
        // padding to horizontal-only and zeroing minimumSize/tapTargetSize
        // here lets this SizedBox's [height] be the single source of truth
        // for total size at any height, with the label centered inside it.
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.textOnPrimary,
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
