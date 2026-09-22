import '../entities/discover_feed_entity.dart';
import '../entities/discover_profile_page.dart';

/// Contract for fetching the Discover feed. A future Node.js + PostgreSQL
/// backed implementation only needs to replace [DiscoverRepositoryImpl] —
/// nothing above this layer changes.
abstract class DiscoverRepository {
  /// The single-page, sectioned feed for the Discover screen.
  Future<DiscoverFeedEntity> getDiscoverFeed();

  /// A flat page of the feed for infinite-scroll surfaces (the Matches reel).
  /// `GET /discover?limit=&cursor=` — pass the previous page's
  /// [DiscoverProfilePage.nextCursor] to continue; omit it for the first page.
  /// [page] is still accepted for callers that only ever read page 1, and is
  /// ignored by the backend whenever a cursor is sent.
  Future<DiscoverProfilePage> getDiscoverProfilesPage({
    int page = 1,
    int limit = 20,
    String? cursor,
  });
}
