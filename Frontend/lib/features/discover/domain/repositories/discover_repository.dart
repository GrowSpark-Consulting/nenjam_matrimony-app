import '../entities/discover_feed_entity.dart';

/// Contract for fetching the Discover feed. A future Node.js + PostgreSQL
/// backed implementation only needs to replace [DiscoverRepositoryImpl] —
/// nothing above this layer changes.
abstract class DiscoverRepository {
  Future<DiscoverFeedEntity> getDiscoverFeed();
}
