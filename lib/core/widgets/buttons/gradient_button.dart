import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_gradients.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';

/// Premium gradient button with primary or gold gradient.
class NmGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double height;
  final bool useGoldGradient;

  const NmGradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 56,
    this.useGoldGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final gradient =
        useGoldGradient ? AppGradients.gold : AppGradients.primary;
    final textColor =
        useGoldGradient ? AppColors.textOnGold : AppColors.textOnPrimary;

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: onPressed != null ? gradient : null,
          color: onPressed == null ? AppColors.textTertiaryLight : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: onPressed != null
              ? (useGoldGradient ? AppShadows.goldGlow : AppShadows.button)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isLoading ? null : onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Center(
              child: isLoading
                  ? SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: textColor,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 20, color: textColor),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
                          style: AppTypography.button.copyWith(
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
