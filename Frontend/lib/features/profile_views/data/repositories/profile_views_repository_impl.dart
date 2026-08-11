import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../domain/entities/profile_viewer_entity.dart';
import '../../domain/repositories/profile_views_repository.dart';

/// Live backend implementation, wired via `profileViewsRepositoryProvider`.
///
/// `GET /matches/profile-views` returns a bare JSON array of
/// `{ profile: DiscoverProfileDto, viewedAt: ISO-8601 }`; `POST
/// /matches/profile-view` records one by `{ profileId }` and returns 204.
class ProfileViewsRepositoryImpl implements ProfileViewsRepository {
  ProfileViewsRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<ProfileViewerEntity>> getViewers({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _apiClient.get<List<dynamic>>(
      ApiEndpoints.matchProfileViews,
      queryParameters: {'page': page, 'limit': limit},
    );
    final data = unwrapOrThrow(response.statusCode, response.data);
    return (data ?? [])
        .cast<Map<String, dynamic>>()
        .map(_viewerFromJson)
        // A row whose timestamp the backend somehow sent unparseable is
        // dropped rather than crashing the whole list.
        .whereType<ProfileViewerEntity>()
        .toList();
  }

  @override
  Future<void> recordView(String profileId) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.matchProfileView,
      data: {'profileId': profileId},
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  ProfileViewerEntity? _viewerFromJson(Map<String, dynamic> json) {
    final profileJson = json['profile'];
    if (profileJson is! Map<String, dynamic>) return null;
    final viewedAt = DateTime.tryParse(json['viewedAt'] as String? ?? '');
    if (viewedAt == null) return null;
    return ProfileViewerEntity(
      profile: DiscoveryProfileModel.fromJson(profileJson),
      // Server timestamps are UTC; the list renders relative times, so
      // convert once here rather than at every call site.
      viewedAt: viewedAt.toLocal(),
    );
  }
}
