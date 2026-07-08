import '../entities/home_feed_entity.dart';

/// Contract for fetching the Home Feed. A future Node.js + PostgreSQL
/// backed implementation only needs to replace [HomeRepositoryImpl] —
/// nothing above this layer changes.
abstract class HomeRepository {
  Future<HomeFeedEntity> getHomeFeed();
}
