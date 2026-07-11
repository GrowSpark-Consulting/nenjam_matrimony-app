import '../../domain/entities/discover_feed_entity.dart';
import '../../domain/repositories/discover_repository.dart';
import '../datasources/discover_mock_datasource.dart';

class DiscoverRepositoryImpl implements DiscoverRepository {
  DiscoverRepositoryImpl(this._dataSource);

  final DiscoverMockDataSource _dataSource;

  @override
  Future<DiscoverFeedEntity> getDiscoverFeed() async {
    // Kick off every call before awaiting so the mock latency overlaps
    // instead of stacking — mirrors how parallel REST/GraphQL calls would
    // be fired against a real backend.
    final storiesFuture = _dataSource.fetchStories();
    final aiRecommendedFuture = _dataSource.fetchAiRecommended();
    final recentlyJoinedFuture = _dataSource.fetchRecentlyJoined();
    final verifiedProfilesFuture = _dataSource.fetchVerifiedProfiles();
    final nearYouFuture = _dataSource.fetchNearYou();
    final premiumMembersFuture = _dataSource.fetchPremiumMembers();
    final completionFuture = _dataSource.fetchProfileCompletionPercent();

    return DiscoverFeedEntity(
      stories: await storiesFuture,
      aiRecommended: await aiRecommendedFuture,
      recentlyJoined: await recentlyJoinedFuture,
      verifiedProfiles: await verifiedProfilesFuture,
      nearYou: await nearYouFuture,
      premiumMembers: await premiumMembersFuture,
      profileCompletionPercent: await completionFuture,
    );
  }
}
