import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../domain/repositories/interests_repository.dart';

/// Real backend implementation — dormant, not wired to any provider.
///
/// TODO(backend): `ApiEndpoints.interestsReceived`/`.interestsSent` are
/// proposed paths, not confirmed with the backend team — the `interests`
/// controller is currently an empty stub (zero routes). Proposed response
/// shape: a bare JSON array of
///   { id, sentAt, status: 'pending'|'accepted'|'declined', profile: DiscoveryProfileDto }
class InterestsRepositoryImpl implements InterestsRepository {
  InterestsRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<InterestRecord>> getReceived({int page = 1, int limit = 20}) =>
      _getList(ApiEndpoints.interestsReceived, page: page, limit: limit);

  @override
  Future<List<InterestRecord>> getSent({int page = 1, int limit = 20}) =>
      _getList(ApiEndpoints.interestsSent, page: page, limit: limit);

  Future<List<InterestRecord>> _getList(
    String path, {
    required int page,
    required int limit,
  }) async {
    final response = await _apiClient.get<List<dynamic>>(
      path,
      queryParameters: {'page': page, 'limit': limit},
    );
    final data = unwrapOrThrow(response.statusCode, response.data);
    return (data ?? [])
        .cast<Map<String, dynamic>>()
        .map((json) => InterestRecord(
              id: json['id'] as String,
              profile: DiscoveryProfileModel.fromJson(
                json['profile'] as Map<String, dynamic>,
              ),
              sentAt: DateTime.parse(json['sentAt'] as String),
              status: InterestStatus.values.firstWhere(
                (s) => s.name == json['status'],
                orElse: () => InterestStatus.pending,
              ),
            ))
        .toList();
  }

  @override
  Future<void> respond(String interestId, {required bool accept}) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.matchInterest,
      data: {'interestId': interestId, 'accept': accept},
    );
    unwrapOrThrow(response.statusCode, response.data);
  }
}
