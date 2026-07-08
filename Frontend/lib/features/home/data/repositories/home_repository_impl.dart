import '../../domain/entities/home_feed_entity.dart';
import '../../domain/repositories/home_repository.dart';
import '../datasources/home_mock_datasource.dart';

class HomeRepositoryImpl implements HomeRepository {
  HomeRepositoryImpl(this._dataSource);

  final HomeMockDataSource _dataSource;

  @override
  Future<HomeFeedEntity> getHomeFeed() async {
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

    return HomeFeedEntity(
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
