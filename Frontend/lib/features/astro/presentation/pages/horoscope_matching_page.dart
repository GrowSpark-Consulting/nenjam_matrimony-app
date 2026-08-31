import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/chips/info_chip.dart';
import '../../../../core/widgets/relationship_intelligence/compatibility_result_widget.dart';
import '../providers/compatibility_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Horoscope Matching — self-summary (Rasi/Nakshatra/Dosham/Birth Details),
/// a matching opt-in toggle, and a compatibility-result preview. Extends
/// the existing horoscope section; does NOT touch `step_horoscope.dart` or
/// the 12-step registration wizard.
class HoroscopeMatchingPage extends ConsumerWidget {
  const HoroscopeMatchingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(myHoroscopeSummaryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).astroMatchingTitle),
      ),
      body: SafeArea(
        child: summaryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) =>
              Center(child: Text(AppLocalizations.of(context).astroLoadError)),
          data: (summary) => SingleChildScrollView(
            padding: AppSpacing.pagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).astroYourDetailsTitle,
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: AppSpacing.cardPaddingLarge,
                  decoration: AppDecorations.card(isDark: isDark),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          if ((summary.rasi ?? '').isNotEmpty)
                            NmInfoChip(
                              label: AppLocalizations.of(
                                context,
                              ).astroRasiLabel(summary.rasi!),
                            ),
                          if ((summary.nakshatra ?? '').isNotEmpty)
                            NmInfoChip(
                              label: AppLocalizations.of(
                                context,
                              ).astroNakshatraLabel(summary.nakshatra!),
                            ),
                          if ((summary.dosham ?? '').isNotEmpty &&
                              summary.dosham != 'NONE')
                            NmInfoChip(
                              label: AppLocalizations.of(
                                context,
                              ).astroDoshamLabel(summary.dosham!),
                            ),
                        ],
                      ),
                      if ((summary.birthTime ?? '').isNotEmpty ||
                          (summary.birthPlace ?? '').isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        if ((summary.birthTime ?? '').isNotEmpty)
                          _DetailRow(
                            label: AppLocalizations.of(
                              context,
                            ).registrationBirthTimeLabel,
                            value: summary.birthTime!,
                          ),
                        if ((summary.birthPlace ?? '').isNotEmpty)
                          _DetailRow(
                            label: AppLocalizations.of(
                              context,
                            ).registrationBirthPlaceLabel,
                            value: summary.birthPlace!,
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: AppSpacing.cardPaddingLarge,
                  decoration: AppDecorations.card(isDark: isDark),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(
                                context,
                              ).astroAllowCompareTitle,
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppLocalizations.of(
                                context,
                              ).astroAllowCompareSubtitle,
                              style: AppTypography.labelSmall.copyWith(
                                color: isDark
                                    ? AppColors.textTertiaryDark
                                    : AppColors.textTertiaryLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: summary.matchingEnabled,
                        onChanged: (value) async {
                          await ref
                              .read(compatibilityRepositoryProvider)
                              .setMatchingEnabled(value);
                          ref.invalidate(myHoroscopeSummaryProvider);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl2),
                Text(
                  AppLocalizations.of(context).astroPreviewTitle,
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  AppLocalizations.of(context).astroPreviewSubtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Consumer(
                  builder: (context, ref, _) {
                    final previewAsync = ref.watch(
                      compatibilityPreviewProvider,
                    );
                    return previewAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (result) =>
                          CompatibilityResultWidget(result: result),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xl2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
