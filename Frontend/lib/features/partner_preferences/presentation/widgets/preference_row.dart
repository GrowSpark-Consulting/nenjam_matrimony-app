import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// A single "label + current value" row inside a Partner Preferences
/// section. Tapping it opens whatever picker (`AppSheets.showSelection`,
/// `showSearchableSelection`, `showMultiSelection`, `showTextInput`, or a
/// custom range sheet) the caller wired up via [onTap] — this widget is
/// purely presentational, keeping every section's rows visually consistent.
class PreferenceRow extends StatelessWidget {
  final String label;
  final String value;
  final String placeholder;
  final VoidCallback onTap;

  const PreferenceRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = 'Not set',
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    hasValue ? value : placeholder,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                      color: hasValue
                          ? AppColors.textPrimaryLight
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondaryLight,
            ),
          ],
        ),
      ),
    );
  }
}
