import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/hero_match_card.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../providers/todays_best_match_provider.dart';

/// Section 1 — Today's Best Match. Independently loading so a slow/failed
/// match pick never blocks the rest of the hub.
class HeroMatchSection extends ConsumerWidget {
  const HeroMatchSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(todaysBestMatchProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.nenjamHubBestMatchTitle,
            style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        async.when(
          data: (profile) => profile == null
              ? const SizedBox.shrink()
              : NmHeroMatchCard(
                  profile: profile,
                  whyLabel: l10n.nenjamHubWhyThisMatch,
                  reasons: _deriveReasons(profile),
                ),
          loading: () => const NmShimmer.card(),
          error: (error, _) => NmErrorWidget(
            onRetry: () => ref.invalidate(todaysBestMatchProvider),
          ),
        ),
      ],
    );
  }

  /// Short, human "why this match" bullets derived from fields already on
  /// the profile — no new backend field required.
  List<String> _deriveReasons(DiscoveryProfileEntity profile) {
    final reasons = <String>[];
    if (profile.community.isNotEmpty) {
      reasons.add('Shares your community — ${profile.community}');
    }
    if (profile.education.isNotEmpty) {
      reasons.add('Similar educational background — ${profile.education}');
    }
    if (profile.diet.isNotEmpty) {
      reasons.add('Compatible lifestyle — ${profile.diet}');
    }
    if (reasons.isEmpty && profile.profession.isNotEmpty) {
      reasons.add(profile.profession);
    }
    return reasons;
  }
}
