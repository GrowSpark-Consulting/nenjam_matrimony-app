import '../../../discover/domain/entities/discovery_profile_entity.dart';

/// One member who viewed the signed-in user's profile, plus when they last
/// did.
///
/// Wraps [DiscoveryProfileEntity] rather than redefining the profile fields —
/// the same approach `ConversationEntity.profile` and `InterestRecord.profile`
/// take — so the viewers list renders with the existing profile card widgets.
class ProfileViewerEntity {
  final DiscoveryProfileEntity profile;

  /// The viewer's most recent view. Repeat views collapse server-side into
  /// one entry carrying the latest timestamp, so this is never a "first
  /// seen" time.
  final DateTime viewedAt;

  const ProfileViewerEntity({required this.profile, required this.viewedAt});
}
