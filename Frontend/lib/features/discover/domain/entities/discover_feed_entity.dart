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

  const DiscoverFeedEntity({
    required this.stories,
    required this.profileCompletionPercent,
    required this.aiRecommended,
    required this.recentlyJoined,
    required this.verifiedProfiles,
    required this.nearYou,
    required this.premiumMembers,
  });
}
