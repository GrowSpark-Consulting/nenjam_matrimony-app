import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/checklist_item_card.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../profile_completion/presentation/providers/profile_completeness_provider.dart';
import '../../../profile_completion/presentation/utils/module_copy.dart';
import '../../../registration/presentation/utils/open_edit_profile.dart';

/// Section 5 — Improve Your Match Quality. A condensed view on top of the
/// existing Profile Completion architecture (no separate tips/logic) —
/// shows the single highest-impact gap plus one more, then hands off to
/// the full Profile Completion screen for everything else.
class ImproveMatchQualitySection extends ConsumerWidget {
  const ImproveMatchQualitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(profileCompletenessSnapshotProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(l10n.nenjamHubImproveTitle,
                  style: AppTypography.titleLarge
                      .copyWith(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => context.push(RouteNames.profileCompletion),
              child: Text(l10n.nenjamHubSeeAll),
            ),
          ],
        ),
        Text(l10n.nenjamHubImproveSubtitle, style: AppTypography.bodyMedium),
        const SizedBox(height: 12),
        async.when(
          data: (completeness) {
            final missing = completeness.missingModules.take(2).toList();
            if (missing.isEmpty) return const SizedBox.shrink();
            return Column(
              children: [
                for (final e in missing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NmChecklistItemCard(
                      icon: moduleIcon(e.module.id),
                      title: moduleTitle(l10n, e.module.id),
                      subtitle: moduleTip(l10n, e.module.id),
                      actionLabel: moduleAction(l10n, e.module.id),
                      isDone: false,
                      onAction: () => openEditProfile(context, ref,
                          wizardStep: e.status.wizardStep),
                    ),
                  ),
              ],
            );
          },
          loading: () => const NmShimmer(height: 80, borderRadius: 20),
          error: (error, _) => NmErrorWidget(
            onRetry: () => ref.invalidate(profileCompletenessSnapshotProvider),
          ),
        ),
      ],
    );
  }
}
