import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'registration_helper_tip.dart';

/// Step 11 — Partner Preference.
///
/// Reuses the exact production Partner Preferences screen
/// (features/partner_preferences/presentation/pages/partner_preferences_page.dart)
/// instead of a duplicate in-wizard form — no duplicate model, repository,
/// provider, or widgets. This card is only an entry point: tapping the
/// button pushes the real page, which reads/writes the same
/// [registrationProvider] state and [RegistrationRepository] the wizard
/// already uses, so no re-hydration is needed here (unlike
/// `openPartnerPreferences()`, which is for the Profile Drawer entry point
/// and calls `startEditMode()` — that would incorrectly flip this in-progress
/// CREATE-mode wizard into EDIT mode). Step remains skippable — Continue
/// never requires this to be touched.
class PartnerPreferenceStepCard extends StatelessWidget {
  final PartnerPreference details;

  const PartnerPreferenceStepCard({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPreferences = details.hasAnyPreference;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationWizardPartnerHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardPartnerHook, style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipPartnerPref),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      hasPreferences ? Icons.check_circle_rounded : Icons.tune_rounded,
                      color: hasPreferences ? AppColors.success : AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hasPreferences
                            ? l10n.registrationPartnerPrefSetLabel
                            : l10n.registrationPartnerPrefNotSetLabel,
                        style: AppTypography.bodyLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.push(RouteNames.partnerPreferences),
                    child: Text(
                      hasPreferences
                          ? l10n.registrationEditPartnerPrefButton
                          : l10n.registrationSetPartnerPrefButton,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
