import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/checklist_item_card.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'registration_helper_tip.dart';

/// Step 12 — Verification Badges & Trust
class StepVerification extends StatelessWidget {
  final VerificationStatus status;
  final void Function(VerificationStatus) onChanged;

  const StepVerification({
    super.key,
    required this.status,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.registrationWizardVerificationHeadline,
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.registrationWizardVerificationHook,
            style: AppTypography.bodyMedium.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipVerification),
          const SizedBox(height: 24),
          NmChecklistItemCard(
            title: l10n.registrationVerifyMobileTitle,
            subtitle: l10n.registrationVerifyMobileSubtitle,
            actionLabel: l10n.registrationVerifyButton,
            icon: Icons.phone_android_rounded,
            isDone: true, // Automatically verified during signup/login
            onAction: () {},
          ),
          const SizedBox(height: 16),
          NmChecklistItemCard(
            title: l10n.registrationVerifyEmailTitle,
            subtitle: l10n.registrationVerifyEmailSubtitle,
            actionLabel: l10n.registrationVerifyButton,
            icon: Icons.email_outlined,
            isDone: status.emailVerified,
            onAction: () {
              onChanged(status.copyWith(emailVerified: true));
            },
          ),
          const SizedBox(height: 16),
          NmChecklistItemCard(
            title: l10n.registrationVerifyFaceTitle,
            subtitle: l10n.registrationVerifyFaceSubtitle,
            actionLabel: l10n.registrationVerifyButton,
            icon: Icons.face_retouching_natural_rounded,
            isDone: status.faceVerified,
            onAction: () {
              onChanged(status.copyWith(faceVerified: true));
            },
          ),
          const SizedBox(height: 16),
          NmChecklistItemCard(
            title: l10n.registrationVerifyIdTitle,
            subtitle: l10n.registrationVerifyIdSubtitle,
            actionLabel: l10n.registrationVerifyButton,
            icon: Icons.verified_user_outlined,
            isDone: status.aadhaarVerified || status.govIdVerified,
            onAction: () {
              onChanged(status.copyWith(aadhaarVerified: true, govIdVerified: true));
            },
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_rounded, color: AppColors.success, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.registrationPrivacyTitle,
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.registrationPrivacySubtitle,
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
