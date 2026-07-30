import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/blocked_user_entity.dart';
import '../../domain/entities/report_reason.dart';
import '../../domain/repositories/safety_repository.dart';
import '../models/blocked_user_model.dart';

class SafetyRepositoryImpl implements SafetyRepository {
  SafetyRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<void> blockUser(String userId) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.blockUser(userId),
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> unblockUser(String userId) async {
    final response = await _apiClient.delete<Map<String, dynamic>>(
      ApiEndpoints.blockUser(userId),
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> reportUser(
    String userId, {
    required ReportReason reason,
    String? description,
  }) async {
    final trimmedDescription = description?.trim();
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.reportUser(userId),
      data: {
        'reason': reason.wireValue,
        if (trimmedDescription != null && trimmedDescription.isNotEmpty)
          'description': trimmedDescription,
      },
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<BlockedUsersPage> getBlockedUsers({int page = 1, int limit = 20}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.blockedUsers,
      queryParameters: {'page': page, 'limit': limit},
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    final items = (data['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(BlockedUserModel.fromJson)
        .toList();
    return BlockedUsersPage(
      items: items,
      page: data['page'] as int? ?? page,
      limit: data['limit'] as int? ?? limit,
      total: data['total'] as int? ?? items.length,
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }
}
