import '../../../discover/domain/entities/discovery_profile_entity.dart';

/// One row of `GET /users/blocked` — the blocked member's card (the same
/// [DiscoveryProfileEntity] shape used everywhere else — Discover, Matches,
/// Interests, Shortlist) plus when the caller blocked them.
class BlockedUserEntity {
  const BlockedUserEntity({required this.profile, required this.blockedAt});

  final DiscoveryProfileEntity profile;
  final DateTime blockedAt;
}

/// Paginated envelope for `GET /users/blocked`.
class BlockedUsersPage {
  const BlockedUsersPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  final List<BlockedUserEntity> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;
}
