import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../buttons/danger_button.dart';
import '../buttons/outlined_button.dart';
import '../buttons/premium_button.dart';
import '../buttons/primary_button.dart';

/// Nenjam Matrimony — Complete Dialogs Kit
abstract final class AppDialogs {
  /// Confirmation Dialog modal.
  static Future<bool?> showConfirmation(
    BuildContext context, {
    required String title,
    required String message,
    // Nullable rather than a const default: a `const` initialiser can't call
    // AppLocalizations, which needs a BuildContext. Callers that pass a label
    // are unaffected; the rest fall back to the localized default resolved
    // against the dialog's own context below.
    String? confirmLabel,
    String? cancelLabel,
  }) {
    return showDialog<bool>(
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
                  label:
                      cancelLabel ?? AppLocalizations.of(context).commonCancel,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NmPrimaryButton(
                  label:
                      confirmLabel ??
                      AppLocalizations.of(context).commonConfirm,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Delete / Destructive Action Dialog.
  static Future<bool?> showDelete(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: AppColors.error),
            const SizedBox(width: 8),
            Text(
              title,
              style: AppTypography.titleLarge.copyWith(color: AppColors.error),
            ),
          ],
        ),
        content: Text(message, style: AppTypography.bodyMedium),
        actions: [
          Row(
            children: [
              Expanded(
                child: NmOutlinedButton(
                  label: AppLocalizations.of(context).commonCancel,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NmDangerButton(
                  label: AppLocalizations.of(context).inboxActionDelete,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Premium Upsell Dialog.
  static Future<void> showPremium(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.workspace_premium_rounded,
              size: 64,
              color: AppColors.accentGold,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).dialogUpgradeTitle,
              style: AppTypography.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).dialogUpgradeMessage,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondaryLight,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            NmPremiumButton(
              label: AppLocalizations.of(context).premiumBannerCta,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Verification Dialog.
  static Future<void> showVerification(
    BuildContext context, {
    required VoidCallback onVerify,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.verified_user_rounded,
              size: 64,
              color: AppColors.verifiedBlue,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).dialogVerificationTitle,
              style: AppTypography.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).dialogVerificationMessage,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondaryLight,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            NmPrimaryButton(
              label: AppLocalizations.of(context).dialogVerifyNow,
              onPressed: () {
                Navigator.pop(context);
                onVerify();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Error Alert Dialog.
  static Future<void> showError(
    BuildContext context, {
    required String message,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context).commonError,
              style: AppTypography.titleLarge,
            ),
          ],
        ),
        content: Text(message, style: AppTypography.bodyMedium),
        actions: [
          NmPrimaryButton(
            label: AppLocalizations.of(context).commonDismiss,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// Success Alert Dialog.
  static Future<void> showSuccess(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: AppColors.success,
            ),
            const SizedBox(width: 8),
            Text(title, style: AppTypography.titleLarge),
          ],
        ),
        content: Text(message, style: AppTypography.bodyMedium),
        actions: [
          NmPrimaryButton(
            label: AppLocalizations.of(context).commonGreat,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// Non-dismissible Progress Dialog.
  static Future<void> showProgress(BuildContext context, {String? message}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(width: 24),
              Expanded(
                child: Text(
                  message ?? AppLocalizations.of(context).commonPleaseWait,
                  style: AppTypography.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
