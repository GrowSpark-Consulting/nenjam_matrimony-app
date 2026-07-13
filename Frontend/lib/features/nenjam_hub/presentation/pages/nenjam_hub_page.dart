import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../providers/daily_insight_provider.dart';
import '../providers/recommendation_rail_provider.dart';
import '../providers/todays_best_match_provider.dart';
import '../widgets/compatibility_report_section.dart';
import '../widgets/conversation_starter_section.dart';
import '../widgets/daily_insight_section.dart';
import '../widgets/hero_match_section.dart';
import '../widgets/improve_match_quality_section.dart';
import '../widgets/keep_growing_section.dart';
import '../widgets/recommendation_rail_section.dart';
import '../widgets/relationship_intelligence_section.dart';

/// Nenjam — the Relationship Intelligence Hub. Composes existing
/// Discover / Psychology / Horoscope / Profile Completion data behind a
/// single daily-use screen; every section owns its own loading/error state
/// so a single slow section never blocks the rest of the page.
class NenjamHubPage extends ConsumerWidget {
  const NenjamHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(discoverFeedProvider);
            ref.invalidate(todaysBestMatchProvider);
            ref.invalidate(recommendationRailProvider);
            ref.invalidate(dailyInsightProvider);
          },
          child: const SingleChildScrollView(
            key: PageStorageKey('nenjam_hub_scroll'),
            padding: AppSpacing.pagePadding,
            physics: AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GreetingHeader(),
                SizedBox(height: AppSpacing.sectionGap),
                HeroMatchSection(),
                SizedBox(height: AppSpacing.sectionGap),
                RelationshipIntelligenceSection(),
                SizedBox(height: AppSpacing.sectionGap),
                CompatibilityReportSection(),
                SizedBox(height: AppSpacing.sectionGap),
                DailyInsightSection(),
                SizedBox(height: AppSpacing.sectionGap),
                ImproveMatchQualitySection(),
                SizedBox(height: AppSpacing.sectionGap),
                ConversationStarterSection(),
                SizedBox(height: AppSpacing.sectionGap),
                RecommendationRailSection(),
                SizedBox(height: AppSpacing.sectionGap),
                KeepGrowingSection(),
                SizedBox(height: AppSpacing.xl2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = (ref.watch(currentAuthUserProvider)?.username ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.isNotEmpty ? l10n.nenjamHubGreeting(name) : l10n.appName,
          style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.nenjamHubGreetingSubtitle,
          style: AppTypography.bodyMedium.copyWith(
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }
}
