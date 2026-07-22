import 'discovery_profile_entity.dart';
import 'story_entity.dart';

/// Aggregate root for everything the Discover feed screen renders.
class DiscoverFeedEntity {
  final List<StoryEntity> stories;
  final int profileCompletionPercent;
  final List<DiscoveryProfileEntity> aiRecommended;
  final List<DiscoveryProfileEntity> recentlyJoined;
  final List<DiscoveryProfileEntity> verifiedProfiles;
  final List<DiscoveryProfileEntity> nearYou;
  final List<DiscoveryProfileEntity> premiumMembers;

  /// True when the backend's ProgressiveFallbackStrategy had to widen the
  /// caller's saved preferences to find any matches (Tier 2+). Drives the
  /// subtle "we widened your search" banner — see `_FallbackBanner` in
  /// discover_page.dart. False means every profile shown is an exact match.
  final bool fallbackUsed;

  /// Human-readable explanation from the backend (e.g. "Age range widened by
  /// 2 years."), shown in the banner when [fallbackUsed] is true. Empty
  /// otherwise.
  final String fallbackReason;

  const DiscoverFeedEntity({
    required this.stories,
    required this.profileCompletionPercent,
    required this.aiRecommended,
    required this.recentlyJoined,
    required this.verifiedProfiles,
    required this.nearYou,
    required this.premiumMembers,
    this.fallbackUsed = false,
    this.fallbackReason = '',
  });
}
