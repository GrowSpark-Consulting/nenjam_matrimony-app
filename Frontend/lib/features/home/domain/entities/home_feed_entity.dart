import 'discovery_profile_entity.dart';
import 'story_entity.dart';

/// Aggregate root for everything the Home Feed screen renders.
class HomeFeedEntity {
  final List<StoryEntity> stories;
  final int profileCompletionPercent;
  final List<DiscoveryProfileEntity> aiRecommended;
  final List<DiscoveryProfileEntity> recentlyJoined;
  final List<DiscoveryProfileEntity> verifiedProfiles;
  final List<DiscoveryProfileEntity> nearYou;
  final List<DiscoveryProfileEntity> premiumMembers;

  const HomeFeedEntity({
    required this.stories,
    required this.profileCompletionPercent,
    required this.aiRecommended,
    required this.recentlyJoined,
    required this.verifiedProfiles,
    required this.nearYou,
    required this.premiumMembers,
  });
}
