import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/daily_insight_card.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/daily_insight_provider.dart';

/// Section 4 — Daily Insight, one personalized sentence that rotates daily.
class DailyInsightSection extends ConsumerWidget {
  const DailyInsightSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(dailyInsightProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.nenjamHubDailyInsightTitle,
            style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        async.when(
          data: (insight) => NmDailyInsightCard(
            title: l10n.nenjamHubDailyInsightTitle,
            message: insight.message,
          ),
          loading: () => const NmShimmer(height: 96, borderRadius: 20),
          error: (error, _) => NmErrorWidget(
            onRetry: () => ref.invalidate(dailyInsightProvider),
          ),
        ),
      ],
    );
  }
}
