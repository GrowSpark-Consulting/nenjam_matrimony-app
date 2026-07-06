import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_gradients.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';

/// Luxury premium gold gradient action button with subtle glow.
class NmPremiumButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double height;

  const NmPremiumButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon = Icons.auto_awesome_rounded,
    this.width,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        gradient: AppGradients.goldButton,
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: onPressed == null || isLoading ? [] : AppShadows.glowGold,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(height / 2),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.textOnGold),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: AppColors.textOnGold),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: AppTypography.button.copyWith(color: AppColors.textOnGold),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
