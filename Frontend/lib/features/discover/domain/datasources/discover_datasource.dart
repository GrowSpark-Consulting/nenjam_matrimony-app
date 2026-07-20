import '../../data/models/discovery_profile_model.dart';
import '../../data/models/story_model.dart';

/// Contract shared by `DiscoverMockDataSource` and `DiscoverRemoteDataSource`
/// — introduced so the two are drop-in interchangeable behind
/// [DiscoverRepositoryImpl] once a real backend `/search` (or dedicated
/// `/discover`) endpoint exists. Not wired anywhere yet: `DiscoverMockDataSource`
/// doesn't implement this today and `DiscoverRepositoryImpl`'s constructor
/// still takes the concrete mock type — flipping both to depend on this
/// interface is a follow-up wiring step, deliberately left undone here so
/// this pass has zero effect on runtime behavior.
abstract interface class DiscoverDataSource {
  Future<List<StoryModel>> fetchStories();
  Future<List<DiscoveryProfileModel>> fetchAiRecommended();
  Future<List<DiscoveryProfileModel>> fetchRecentlyJoined();
  Future<List<DiscoveryProfileModel>> fetchVerifiedProfiles();
  Future<List<DiscoveryProfileModel>> fetchNearYou();
  Future<List<DiscoveryProfileModel>> fetchPremiumMembers();
  Future<int> fetchProfileCompletionPercent();
}
