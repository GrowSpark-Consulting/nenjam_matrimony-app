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
import '../../../profile/domain/models/profile.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../domain/models/profile_draft.dart';
import '../providers/registration_provider.dart';

/// The four facts the celebration cards report, resolved from whichever
/// source is currently authoritative.
///
/// The finalized backend profile (`GET /profiles/me`) is the real source;
/// the local wizard draft only stands in for the first frame so the screen
/// never opens on a spinner after a successful registration.
class _SuccessSummary {
  final int completionPercent;
  final bool hasPhotos;
  final bool hasHoroscope;
  final bool hasPartnerPreference;

  const _SuccessSummary({
    required this.completionPercent,
    required this.hasPhotos,
    required this.hasHoroscope,
    required this.hasPartnerPreference,
  });

  /// Reads `completion.percentage` rather than `profileCompletePct`:
  /// ProfileService.getOwn() recomputes `completion` live on every read,
  /// while `profileCompletePct` is a persisted column refreshed only by
  /// writes. Immediately after finalize the live figure is the accurate one.
  static _SuccessSummary fromProfile(Profile profile) => _SuccessSummary(
        completionPercent: profile.completion.percentage,
        hasPhotos: profile.photos.isNotEmpty,
        hasHoroscope: _profileHasHoroscope(profile.astrology),
        hasPartnerPreference:
            _profileHasPartnerPreference(profile.partnerPreference),
      );

  static _SuccessSummary fromDraft(ProfileDraft draft) {
    final pref = draft.partnerPreference;
    return _SuccessSummary(
      completionPercent: draft.completionPercentage.round(),
      hasPhotos: draft.photoGallery.primaryPhotoPath != null ||
          draft.photoGallery.galleryPaths.isNotEmpty,
      hasHoroscope: draft.horoscopeDetails.horoscopeAvailable,
      hasPartnerPreference: pref.preferredAgeRange.isNotEmpty ||
          pref.preferredHeightRange.isNotEmpty ||
          pref.religionPref.isNotEmpty ||
          pref.castePref.isNotEmpty ||
          pref.educationPref.isNotEmpty ||
          pref.locationPref.isNotEmpty,
    );
  }

  /// True when the user actually supplied birth details — `rasi` or
  /// `nakshatra` present, or the backend's own `horoscopeAvailable` flag.
  static bool _profileHasHoroscope(AstrologyInfo? astrology) {
    if (astrology == null) return false;
    return astrology.horoscopeAvailable ||
        (astrology.rasi?.trim().isNotEmpty ?? false) ||
        (astrology.nakshatra?.trim().isNotEmpty ?? false);
  }

  /// Deliberately ignores the age/height ranges: the API always returns
  /// defaults for those (18-45, 140-210cm), so they cannot distinguish "the
  /// user set a preference" from "the user never opened the screen". Only
  /// the list fields and income carry that signal.
  static bool _profileHasPartnerPreference(PartnerPreferenceInfo? pref) {
    if (pref == null) return false;
    return pref.preferredReligions.isNotEmpty ||
        pref.preferredCastes.isNotEmpty ||
        pref.preferredCities.isNotEmpty ||
        pref.preferredEducation.isNotEmpty ||
        pref.preferredOccupations.isNotEmpty ||
        pref.preferredMotherTongues.isNotEmpty ||
        pref.maritalStatusPref.isNotEmpty ||
        (pref.minIncomeLakhs?.isNotEmpty ?? false);
  }
}

/// "Welcome to Nenjam ❤️" — the celebration screen shown once, after the
/// completing screen finishes the real save.
///
/// Every figure comes from the finalized profile returned by
/// `GET /profiles/me` via [myProfileProvider]. The local
/// [registrationProvider] draft is used only as an instant first paint
/// while that request is in flight (and as a fallback if it fails), so the
/// user never waits on a spinner to see their own completion score.
class RegistrationSuccessPage extends ConsumerWidget {
  const RegistrationSuccessPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final draft = ref.watch(registrationProvider);
    final profileAsync = ref.watch(myProfileProvider);

    // First name is the emptiness probe, not completionPercentage: a blank
    // ProfileDraft already scores ~11% because `profileCreatedFor` defaults
    // to 'Myself' and `country` to 'India'. An empty first name means the
    // wizard was never filled in here — the user reached this route cold
    // (deep link, or a process restart that cleared the draft).
    final draftSummary = draft.basicDetails.firstName.trim().isNotEmpty
        ? _SuccessSummary.fromDraft(draft)
        : null;

    // Backend data wins the moment it lands; until then the draft carries
    // the screen. This is the "local first, refresh in background" path —
    // there is no second call, just one request whose result upgrades what
    // is already on screen.
    final summary = profileAsync.maybeWhen(
      data: _SuccessSummary.fromProfile,
      orElse: () => draftSummary,
    );

    if (summary == null) {
      return _Shell(
        child: profileAsync.hasError
            ? _ErrorState(
                isDark: isDark,
                l10n: l10n,
                onRetry: () => ref.invalidate(myProfileProvider),
              )
            : const _LoadingState(),
      );
    }

    return _Shell(child: _Celebration(summary: summary, isDark: isDark, l10n: l10n));
  }
}

/// Page chrome shared by the loading, error and celebration states so all
/// three keep identical padding and safe-area handling.
class _Shell extends StatelessWidget {
  final Widget child;

  const _Shell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: child,
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// Only reachable when there is no draft to fall back on. Offers a retry,
/// but still lets the user into the app — a failed summary fetch must not
/// trap someone whose registration already succeeded.
class _ErrorState extends StatelessWidget {
  final bool isDark;
  final AppLocalizations l10n;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.isDark,
    required this.l10n,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            l10n.registrationCompletingErrorTitle,
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(l10n.commonRetry),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: NmGradientButton(
              label: l10n.registrationSuccessCta,
              useGoldGradient: true,
              icon: Icons.favorite_rounded,
              onPressed: () => context.go(RouteNames.discover),
            ),
          ),
        ],
      ),
    );
  }
}

/// The celebration layout — unchanged from the original design; only the
/// values it renders now come from [_SuccessSummary].
class _Celebration extends StatelessWidget {
  final _SuccessSummary summary;
  final bool isDark;
  final AppLocalizations l10n;

  const _Celebration({
    required this.summary,
    required this.isDark,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        Icons.workspace_premium_rounded,
        l10n.registrationSuccessCompletionCard(summary.completionPercent),
      ),
      (
        Icons.photo_library_rounded,
        summary.hasPhotos
            ? l10n.registrationSuccessPhotosAdded
            : l10n.registrationSuccessPhotosSkipped,
      ),
      (
        Icons.stars_rounded,
        summary.hasHoroscope
            ? l10n.registrationSuccessHoroscopeDone
            : l10n.registrationSuccessHoroscopeSkipped,
      ),
      if (summary.hasPartnerPreference)
        (Icons.handshake_rounded, l10n.registrationSuccessPartnerPrefSaved),
    ];

    return Column(
      children: [
        const Spacer(flex: 2),
        const Icon(Icons.favorite_rounded, size: 64, color: AppColors.accentGold)
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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
    );
  }
}
