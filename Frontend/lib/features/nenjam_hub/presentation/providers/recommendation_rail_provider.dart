import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import 'todays_best_match_provider.dart';

/// "Today's Recommendation" horizontal rail — the same Discover feed,
/// ranked by overall compatibility, excluding whichever profile is
/// already shown as the hero "Today's Best Match" so nothing repeats.
final recommendationRailProvider =
    FutureProvider.autoDispose<List<DiscoveryProfileEntity>>((ref) async {
  final feed = await ref.watch(discoverFeedProvider.future);
  final bestMatch = await ref.watch(todaysBestMatchProvider.future);

  final candidates = [
    ...feed.aiRecommended,
    ...feed.verifiedProfiles,
    ...feed.premiumMembers,
    ...feed.nearYou,
    ...feed.recentlyJoined,
  ];

  final seen = <String>{if (bestMatch != null) bestMatch.id};
  final deduped = <DiscoveryProfileEntity>[];
  for (final profile in candidates) {
    if (seen.add(profile.id)) deduped.add(profile);
  }
  deduped.sort((a, b) => b.compatibility.overallCompatibility
      .compareTo(a.compatibility.overallCompatibility));

  return deduped.take(5).toList();
});
