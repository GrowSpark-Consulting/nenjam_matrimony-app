import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Reusable social sign-in button (e.g., Google, Apple) matching design tokens.
class NmSocialButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? iconWidget;
  final String? assetPath;
  final bool isLoading;

  const NmSocialButton({
    super.key,
    required this.label,
    this.onPressed,
    this.iconWidget,
    this.assetPath,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFFC5C6CF),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (iconWidget != null) ...[
                  iconWidget!,
                  const SizedBox(width: 12),
                ] else if (assetPath != null) ...[
                  Image.asset(assetPath!, width: 24, height: 24),
                  const SizedBox(width: 12),
                ] else ...[
                  const Icon(Icons.g_mobiledata, size: 28, color: AppColors.primary),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(
                    color: isDark ? AppColors.textPrimaryDark : const Color(0xFF1B1C19),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
