import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';
import '../cards/horoscope_card.dart';
import '../chips/info_chip.dart';

/// Horoscope Compatibility — dual-mode display:
///  * **Self-summary** (default, [compatibilityScore] == null): shows the
///    member's own rasi/nakshatra/dosham + matching opt-in status. Used in
///    the registration wizard (Step 15) and on [ProfilePage] — there is no
///    partner to compare against on your own profile.
///  * **Comparison** ([compatibilityScore] != null): reuses [NmHoroscopeCard]
///    to show a 2-person score. Not wired to any screen yet — the seam a
///    future "view other member" screen and the matches module can use via
///    `GET /astro/compatibility/:targetUserId`.
class HoroscopeCompatibilitySection extends StatelessWidget {
  // Self-summary mode
  final String? rasi;
  final String? nakshatra;
  final String? dosham;
  final bool matchingEnabled;

  // Comparison mode
  final int? compatibilityScore;
  final List<String>? matchingPoints;
  final String? partnerName;
  final VoidCallback? onTap;

  const HoroscopeCompatibilitySection({
    super.key,
    this.rasi,
    this.nakshatra,
    this.dosham,
    this.matchingEnabled = true,
    this.compatibilityScore,
    this.matchingPoints,
    this.partnerName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (compatibilityScore != null) {
      return NmHoroscopeCard(
        partnerName: partnerName ?? 'Match',
        gunaScore: compatibilityScore!,
        maxScore: 100,
        summary: matchingPoints?.isNotEmpty == true
            ? matchingPoints!.first
            : 'Tap to see the full compatibility breakdown',
        onTap: onTap,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasData =
        (rasi?.isNotEmpty ?? false) || (nakshatra?.isNotEmpty ?? false);

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPaddingLarge,
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.accentGold,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'Your Horoscope',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasData)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (rasi?.isNotEmpty ?? false) NmInfoChip(label: rasi!),
                if (nakshatra?.isNotEmpty ?? false)
                  NmInfoChip(label: nakshatra!),
                if ((dosham?.isNotEmpty ?? false) && dosham != 'NONE')
                  NmInfoChip(label: dosham!),
              ],
            )
          else
            Text(
              'Add your horoscope details to enable compatibility matching.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                matchingEnabled
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                size: 16,
                color: matchingEnabled
                    ? AppColors.success
                    : AppColors.textTertiaryLight,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  matchingEnabled
                      ? 'Horoscope matching enabled'
                      : 'Horoscope matching disabled',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
