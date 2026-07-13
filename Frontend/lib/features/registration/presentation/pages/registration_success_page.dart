import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/registration_provider.dart';

/// "Welcome to Nenjam ❤️" — the celebration screen shown once, after the
/// completing screen finishes the real save. Reads [registrationProvider]
/// purely for display (completion %, photos, horoscope, partner prefs) —
/// never mutates state.
class RegistrationSuccessPage extends ConsumerWidget {
  const RegistrationSuccessPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final draft = ref.watch(registrationProvider);

    final hasPhotos = draft.photoGallery.primaryPhotoPath != null ||
        draft.photoGallery.galleryPaths.isNotEmpty;
    final hasHoroscope = draft.horoscopeDetails.horoscopeAvailable;
    final pref = draft.partnerPreference;
    final hasPartnerPref = pref.preferredAgeRange.isNotEmpty ||
        pref.preferredHeightRange.isNotEmpty ||
        pref.religionPref.isNotEmpty ||
        pref.castePref.isNotEmpty ||
        pref.educationPref.isNotEmpty ||
        pref.locationPref.isNotEmpty;

    final cards = [
      (
        Icons.workspace_premium_rounded,
        l10n.registrationSuccessCompletionCard(
            draft.completionPercentage.toInt()),
      ),
      (
        Icons.photo_library_rounded,
        hasPhotos
            ? l10n.registrationSuccessPhotosAdded
            : l10n.registrationSuccessPhotosSkipped,
      ),
      (
        Icons.stars_rounded,
        hasHoroscope
            ? l10n.registrationSuccessHoroscopeDone
            : l10n.registrationSuccessHoroscopeSkipped,
      ),
      if (hasPartnerPref)
        (Icons.handshake_rounded, l10n.registrationSuccessPartnerPrefSaved),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const Icon(Icons.favorite_rounded,
                      size: 64, color: AppColors.accentGold)
                  .animate()
                  .scale(duration: const Duration(milliseconds: 500)),
              const SizedBox(height: 24),
              Text(
                l10n.registrationSuccessHeadline,
                textAlign: TextAlign.center,
                style:
                    AppTypography.headlineLarge.copyWith(fontWeight: FontWeight.w700),
              ).animate().fadeIn(delay: const Duration(milliseconds: 150)),
              const SizedBox(height: 12),
              Text(
                l10n.registrationSuccessSubtitle,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ).animate().fadeIn(delay: const Duration(milliseconds: 300)),
              const SizedBox(height: 32),
              for (var i = 0; i < cards.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: AppDecorations.cardSubtle(isDark: isDark),
                    child: Row(
                      children: [
                        Icon(cards[i].$1, color: AppColors.primary, size: 22),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            cards[i].$2,
                            style: AppTypography.bodyMedium
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(
                    delay: Duration(milliseconds: 450 + i * 120),
                    duration: const Duration(milliseconds: 350)),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: NmGradientButton(
                  label: l10n.registrationSuccessCta,
                  useGoldGradient: true,
                  icon: Icons.favorite_rounded,
                  onPressed: () => context.go(RouteNames.discover),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
