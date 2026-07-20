import 'discovery_profile_entity.dart';

/// A "New Today" circular avatar shown at the top of the Discover feed.
///
/// Despite the "story" naming (a holdover from the original Stitch design
/// reference), these represent newly-joined members, not ephemeral
/// stories — [profile] carries the full member record so tapping one
/// opens that member's Profile Detail page like any other profile card.
class StoryEntity {
  final String id;
  final String name;
  final String imageUrl;
  final bool hasNewStory;

  /// 'Male' / 'Female' / '' — picks the gender-aware placeholder icon
  /// when [imageUrl] fails to load.
  final String gender;

  /// The full member this bubble represents. Nullable only so a
  /// hypothetical future purely-decorative story (no backing member)
  /// doesn't force every call site to fabricate one — every "New Today"
  /// entry populated by the mock/real data source today always sets this.
  final DiscoveryProfileEntity? profile;

  const StoryEntity({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.hasNewStory = false,
    this.gender = '',
    this.profile,
  });
}
