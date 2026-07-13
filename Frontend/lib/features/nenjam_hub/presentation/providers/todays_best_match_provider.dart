import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../discover/presentation/providers/discover_providers.dart';

/// Today's single hero recommendation for the Nenjam hub — derived from
/// the same Discover feed Discover/Matches already use, so there is no
/// separate matching repository to maintain. Picks among the top few
/// candidates by overall compatibility, keyed by the day of year, so the
/// choice is stable for the rest of the calendar day (no reshuffle on
/// pull-to-refresh) while still varying from day to day.
final todaysBestMatchProvider =
    FutureProvider.autoDispose<DiscoveryProfileEntity?>((ref) async {
  final feed = await ref.watch(discoverFeedProvider.future);
  final candidates = [
    ...feed.aiRecommended,
    ...feed.verifiedProfiles,
    ...feed.premiumMembers,
  ];
  if (candidates.isEmpty) return null;

  final sorted = [...candidates]..sort((a, b) => b.compatibility
      .overallCompatibility
      .compareTo(a.compatibility.overallCompatibility));

  final dayIndex = DateTime.now().difference(DateTime(2024, 1, 1)).inDays;
  final poolSize = sorted.length < 3 ? sorted.length : 3;
  return sorted[dayIndex % poolSize];
});
