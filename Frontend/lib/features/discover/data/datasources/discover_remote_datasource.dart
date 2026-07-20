import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/datasources/discover_datasource.dart';
import '../models/discovery_profile_model.dart';
import '../models/story_model.dart';

/// Real backend implementation — dormant, not wired to any provider.
/// `DiscoverRepositoryImpl` still depends on the concrete
/// `DiscoverMockDataSource`; nothing constructs this class today.
///
/// TODO(backend): the `search` controller (and there is no dedicated
/// `discover` controller at all) is currently an empty stub — zero routes.
/// Proposed contract, to confirm with the backend team before they build
/// it:
///   GET /search?category={ai|recent|verified|nearby|premium|newToday}&page=1&limit=20
///   -> { items: DiscoveryProfileDto[], page, limit, total, hasMore }
/// where `DiscoveryProfileDto` mirrors [DiscoveryProfileModel]'s fields
/// (see that class's `fromJson`). `newToday` additionally wraps each item
/// in [StoryModel]'s shape (`imageUrl`/`hasNewStory` alongside `profile`).
/// Every method here calls that single parameterized endpoint with a fixed
/// `page=1&limit=20` for now — real pagination wiring is a follow-up once
/// this is actually plugged into `discoverFeedProvider`.
class DiscoverRemoteDataSource implements DiscoverDataSource {
  DiscoverRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  static const _defaultLimit = 20;

  Future<List<dynamic>> _fetchCategory(String category) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.search,
      queryParameters: {
        'category': category,
        'page': 1,
        'limit': _defaultLimit,
      },
    );
    final data = unwrapOrThrow(response.statusCode, response.data);
    return (data?['items'] as List<dynamic>?) ?? const [];
  }

  @override
  Future<List<StoryModel>> fetchStories() async {
    final items = await _fetchCategory('newToday');
    return items
        .cast<Map<String, dynamic>>()
        .map(StoryModel.fromJson)
        .toList();
  }

  @override
  Future<List<DiscoveryProfileModel>> fetchAiRecommended() =>
      _fetchProfiles('ai');

  @override
  Future<List<DiscoveryProfileModel>> fetchRecentlyJoined() =>
      _fetchProfiles('recent');

  @override
  Future<List<DiscoveryProfileModel>> fetchVerifiedProfiles() =>
      _fetchProfiles('verified');

  @override
  Future<List<DiscoveryProfileModel>> fetchNearYou() =>
      _fetchProfiles('nearby');

  @override
  Future<List<DiscoveryProfileModel>> fetchPremiumMembers() =>
      _fetchProfiles('premium');

  Future<List<DiscoveryProfileModel>> _fetchProfiles(String category) async {
    final items = await _fetchCategory(category);
    return items
        .cast<Map<String, dynamic>>()
        .map(DiscoveryProfileModel.fromJson)
        .toList();
  }

  @override
  Future<int> fetchProfileCompletionPercent() {
    // Doesn't belong to Discover's domain at all — the real, working
    // completion percentage already lives in the `profile_completion`
    // feature's aggregator (see profile_completion_aggregator.dart), backed
    // by the real GET /profiles/draft endpoint. Left unimplemented rather
    // than invented so nothing silently calls a made-up number.
    throw UnimplementedError(
      'TODO(backend): Discover should not own profile-completion data — '
      'see profile_completion feature\'s real aggregator instead.',
    );
  }
}
