import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/compatibility_report_card.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/todays_best_match_provider.dart';

/// Section 3 — Compatibility Report for the same profile shown as
/// "Today's Best Match", broken down across multiple axes.
class CompatibilityReportSection extends ConsumerWidget {
  const CompatibilityReportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(todaysBestMatchProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.nenjamHubCompatibilityReportTitle,
            style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        async.when(
          data: (profile) {
            if (profile == null) return const SizedBox.shrink();
            final c = profile.compatibility;
            return NmCompatibilityReportCard(
              overallScore: c.overallCompatibility,
              overallLabel:
                  l10n.nenjamHubCompatibilityReportSubtitle(profile.name),
              showMoreLabel: l10n.nenjamHubShowMore,
              showLessLabel: l10n.nenjamHubShowLess,
              axes: [
                CompatibilityAxis(
                    label: l10n.nenjamHubAxisPsychology,
                    score: c.psychologyMatchPercent),
                CompatibilityAxis(
                    label: l10n.nenjamHubAxisAstrology,
                    score: c.astroMatchPercent),
                CompatibilityAxis(
                    label: l10n.nenjamHubAxisLifestyle,
                    score: c.lifestyleMatchPercent),
                CompatibilityAxis(
                    label: l10n.nenjamHubAxisFamily,
                    score: c.familyMatchPercent),
                CompatibilityAxis(
                    label: l10n.nenjamHubAxisEducation,
                    score: c.educationMatchPercent),
                CompatibilityAxis(
                    label: l10n.nenjamHubAxisValues,
                    score: c.valuesMatchPercent),
                CompatibilityAxis(
                    label: l10n.nenjamHubAxisGoals,
                    score: c.goalsMatchPercent),
              ],
            );
          },
          loading: () => const NmShimmer.card(),
          error: (error, _) => NmErrorWidget(
            onRetry: () => ref.invalidate(todaysBestMatchProvider),
          ),
        ),
      ],
    );
  }
}
