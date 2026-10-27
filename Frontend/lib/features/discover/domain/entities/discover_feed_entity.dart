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

  /// Where the feed continues after this page, as the backend named it. Null
  /// once the feed is exhausted. AI Recommended pages on from here — see
  /// `discoverMoreProfilesProvider`.
  final String? nextCursor;

  /// Whether the backend reported more matches past this page.
  final bool hasMore;

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
    this.nextCursor,
    this.hasMore = false,
  });

  /// Every profile id this page placed anywhere on the screen, so a later
  /// page can skip members already shown (each card's Hero tag must be unique).
  Set<String> get profileIds => {
    for (final s in stories) s.id,
    for (final p in aiRecommended) p.id,
    for (final p in recentlyJoined) p.id,
    for (final p in verifiedProfiles) p.id,
    for (final p in nearYou) p.id,
    for (final p in premiumMembers) p.id,
  };
}
