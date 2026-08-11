import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../buttons/outlined_button.dart';
import '../buttons/primary_button.dart';

/// Pre-permission and permanently-denied dialogs shared by every permission
/// flow (camera, notifications, ...). Kept separate from [AppDialogs] since
/// these two are a matched pair specific to the permission lifecycle, but
/// styled identically (same rounded [AlertDialog] shell, same button kit).

/// Shows context BEFORE the OS permission popup. Returns `true` if the user
/// chose to proceed (caller should then call
/// `AppPermissionService.request`), `false`/`null` for "Not now"/dismiss.
Future<bool> showPermissionPrimerDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  String proceedLabel = 'Enable',
  String cancelLabel = 'Not now',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTypography.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondaryLight,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: NmOutlinedButton(
                  label: cancelLabel,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NmPrimaryButton(
                  label: proceedLabel,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Shown once a permission is permanently denied — the OS will no longer
/// show its own prompt, so the only path forward is the Settings app.
Future<void> showOpenSettingsDialog(
  BuildContext context, {
  required String title,
  required String message,
  required Future<bool> Function() onOpenSettings,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(title, style: AppTypography.titleLarge),
      content: Text(message, style: AppTypography.bodyMedium),
      actions: [
        Row(
          children: [
            Expanded(
              child: NmOutlinedButton(
                label: AppLocalizations.of(context).commonCancel,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NmPrimaryButton(
                label: AppLocalizations.of(context).commonOpenSettings,
                onPressed: () {
                  Navigator.pop(context);
                  onOpenSettings();
                },
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
