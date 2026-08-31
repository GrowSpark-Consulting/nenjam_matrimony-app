import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/feedback/empty_state.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../core/widgets/indicators/nm_score_ring.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../profile/presentation/widgets/verification_card.dart';
import '../../../profile_detail/domain/entities/trust_score_entity.dart';
import '../providers/trust_score_providers.dart';

class TrustScorePage extends ConsumerWidget {
  const TrustScorePage({super.key});

  NmVerificationStatus _mapStatus(TrustItemStatus status) => switch (status) {
    TrustItemStatus.verified => NmVerificationStatus.verified,
    TrustItemStatus.pending => NmVerificationStatus.pending,
    TrustItemStatus.incomplete => NmVerificationStatus.incomplete,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scoreAsync = ref.watch(myTrustScoreProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.drawerTrustScore)),
      body: RefreshIndicator(
        color: AppColors.secondary,
        onRefresh: () => ref.refresh(myTrustScoreProvider.future),
        child: scoreAsync.when(
          data: (score) => _TrustScoreContent(
            score: score,
            isDark: isDark,
            mapStatus: _mapStatus,
          ),
          loading: () => const _TrustScoreSkeleton(),
          error: (error, _) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: 480,
              child: NmEmptyState(
                icon: Icons.star_outline_rounded,
                title: AppLocalizations.of(context).trustScoreUnavailableTitle,
                message: AppLocalizations.of(
                  context,
                ).trustScoreUnavailableMessage,
                action: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(myTrustScoreProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(AppLocalizations.of(context).commonRetry),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrustScoreContent extends StatelessWidget {
  final TrustScoreEntity score;
  final bool isDark;
  final NmVerificationStatus Function(TrustItemStatus) mapStatus;

  const _TrustScoreContent({
    required this.score,
    required this.isDark,
    required this.mapStatus,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                NmScoreRing(
                  value: score.overallPercent / 100,
                  displayText: '${score.overallPercent}',
                  color: AppColors.secondary,
                  textColor: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.primary,
                  size: 140,
                  strokeWidth: 10,
                  fontSize: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).trustScoreTitle,
                  style: AppTypography.titleMedium.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (score.items.isNotEmpty)
            NmVerificationCard(
              items: [
                for (final item in score.items)
                  NmVerificationItem(
                    icon: item.icon,
                    label: item.label,
                    status: mapStatus(item.status),
                  ),
              ],
            )
          else
            NmEmptyState(
              icon: Icons.checklist_rtl_rounded,
              title: AppLocalizations.of(context).trustScoreEmptyTitle,
              message: AppLocalizations.of(context).trustScoreEmptyMessage,
            ),
        ],
      ),
    );
  }
}

class _TrustScoreSkeleton extends StatelessWidget {
  const _TrustScoreSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Center(child: NmShimmer.circle(size: 140)),
        const SizedBox(height: 32),
        const NmShimmer(height: 180, borderRadius: 20),
      ],
    );
  }
}
