import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Loading indicator widget with optional message.
class NmLoadingWidget extends StatelessWidget {
  final String? message;
  final double size;
  final Color? color;

  const NmLoadingWidget({
    super.key,
    this.message,
    this.size = 40,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: color ??
                  (isDark
                      ? const Color(0xFF7B9AD6)
                      : AppColors.primary),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
