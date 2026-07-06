import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Nenjam Matrimony — Reusable Bottom Sheets Kit
abstract final class AppSheets {
  /// Base styled Bottom Sheet wrapper.
  static Future<T?> show<T>(BuildContext context, {required Widget child, String? title}) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
              if (title != null) ...[
                Padding(padding: const EdgeInsets.all(20), child: Text(title, style: AppTypography.titleLarge)),
                const Divider(height: 1),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }

  /// Reusable Selection Sheet.
  static Future<String?> showSelection(BuildContext context, {required String title, required List<String> options, String? selectedValue}) {
    return show<String>(
      context,
      title: title,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: options.length,
        itemBuilder: (context, index) {
          final opt = options[index];
          final isSelected = opt == selectedValue;
          return ListTile(
            title: Text(opt, style: AppTypography.bodyMedium.copyWith(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400, color: isSelected ? AppColors.primary : null)),
            trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
            onTap: () => Navigator.pop(context, opt),
          );
        },
      ),
    );
  }

  /// Gender Selection Sheet.
  static Future<String?> showGender(BuildContext context, {String? selected}) {
    return showSelection(context, title: 'Select Gender', options: ['Male', 'Female'], selectedValue: selected);
  }

  /// Religion Selection Sheet.
  static Future<String?> showReligion(BuildContext context, {String? selected}) {
    return showSelection(context, title: 'Select Religion', options: ['Hindu', 'Christian', 'Muslim', 'Jain', 'Sikh'], selectedValue: selected);
  }

  /// Language Selection Sheet.
  static Future<String?> showLanguage(BuildContext context, {String? selected}) {
    return showSelection(context, title: 'Mother Tongue', options: ['Tamil', 'Telugu', 'Malayalam', 'Kannada', 'Hindi', 'English'], selectedValue: selected);
  }

  /// Date Sheet picker modal.
  static Future<DateTime?> showDate(BuildContext context, {DateTime? initialDate}) async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime(now.year - 25),
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year - 18),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.primary, onPrimary: Colors.white)),
        child: child!,
      ),
    );
  }
}
