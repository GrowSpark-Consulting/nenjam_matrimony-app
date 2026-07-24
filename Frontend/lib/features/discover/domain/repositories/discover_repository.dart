import '../entities/discover_feed_entity.dart';
import '../entities/discover_profile_page.dart';

/// Contract for fetching the Discover feed. A future Node.js + PostgreSQL
/// backed implementation only needs to replace [DiscoverRepositoryImpl] —
/// nothing above this layer changes.
abstract class DiscoverRepository {
  /// The single-page, sectioned feed for the Discover screen.
  Future<DiscoverFeedEntity> getDiscoverFeed();

  /// A flat page of the feed for infinite-scroll surfaces (the Matches reel).
  /// `GET /discover?page=&limit=` — the backend already returns `hasMore`.
  Future<DiscoverProfilePage> getDiscoverProfilesPage({
    int page = 1,
    int limit = 20,
  });
}
