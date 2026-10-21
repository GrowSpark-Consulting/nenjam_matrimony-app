import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// Horoscope Matching — not available yet, and says so.
///
/// This page used to show a horoscope summary, a matching opt-in switch and a
/// compatibility result, all read from `MockCompatibilityRepository`: invented
/// Rasi/Nakshatra values and a canned score presented as the member's own. The
/// backend's `astro` module has no routes and is not mounted (see
/// `ApiCompatibilityRepository`), so there is no real data to show. Until there
/// is, the page states that plainly instead of simulating a result.
///
/// To bring the feature back: build the backend endpoints, point
/// `compatibilityRepositoryProvider` at `ApiCompatibilityRepository`, and
/// restore the summary / opt-in / result sections from version control.
class HoroscopeMatchingPage extends StatelessWidget {
  const HoroscopeMatchingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.astroMatchingTitle)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: AppSpacing.pagePadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.stars_rounded,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.base),
                Text(
                  l10n.astroUnavailableTitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.astroUnavailableMessage,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondaryLight,
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
