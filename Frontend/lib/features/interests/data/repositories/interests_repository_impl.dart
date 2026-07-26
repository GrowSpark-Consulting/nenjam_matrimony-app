import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/repositories/interests_repository.dart';

/// Live backend implementation, wired via `interestsRepositoryProvider`.
/// `POST /matches/interest` sends / accepts / declines; `GET /interests/received`
/// and `/sent` return bare arrays of
/// `{ id, sentAt, status, profile }`; `DELETE /interests/:id` withdraws.
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

  @override
  Future<InterestRecord> sendInterest(DiscoveryProfileEntity profile) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.matchInterest,
      data: {'profileId': profile.id},
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return InterestRecord(
      id: data['id'] as String,
      profile: profile,
      sentAt: data['sentAt'] != null
          ? DateTime.parse(data['sentAt'] as String)
          : DateTime.now(),
      status: InterestStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => InterestStatus.pending,
      ),
    );
  }

  @override
  Future<void> withdraw(String interestId) async {
    final response = await _apiClient.delete<Map<String, dynamic>>(
      '${ApiEndpoints.interests}/$interestId',
    );
    unwrapOrThrow(response.statusCode, response.data);
  }
}
