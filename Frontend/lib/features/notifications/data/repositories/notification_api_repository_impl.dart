import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/repositories/notification_repository.dart';
import '../models/notification_model.dart';

/// Live backend implementation, wired via `notificationRepositoryProvider`.
///
/// Endpoints (backend `notifications` module):
///  - `GET /notifications?page&limit` -> `{ items, page, limit, total, hasMore }`,
///    each item shaped per `NotificationModel.fromJson`.
///  - `GET /notifications/unread-count` -> `{ count }`.
///  - `PATCH /notifications/:id/read` -> marks one read.
///  - `PATCH /notifications/read-all` -> marks every notification read.
///  - `POST /notifications/device` -> registers/reactivates an FCM token.
///  - `DELETE /notifications/device` -> deactivates an FCM token.
class NotificationApiRepositoryImpl implements NotificationRepository {
  NotificationApiRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<NotificationResultPage> getNotifications({int page = 1, int limit = 20}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.notifications,
      queryParameters: {'page': page, 'limit': limit},
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    final items = (data['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(NotificationModel.fromJson)
        .toList();
    return NotificationResultPage(
      items: items,
      page: data['page'] as int? ?? page,
      limit: data['limit'] as int? ?? limit,
      total: data['total'] as int? ?? items.length,
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }

  @override
  Future<int> getUnreadCount() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '${ApiEndpoints.notifications}/unread-count',
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return data['count'] as int? ?? 0;
  }

  @override
  Future<void> markRead(String id) async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      '${ApiEndpoints.notifications}/$id/read',
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> markAllRead() async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      '${ApiEndpoints.notifications}/read-all',
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> registerDevice({
    required String fcmToken,
    required String platform,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.registerDevice,
      data: {'fcmToken': fcmToken, 'platform': platform},
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> unregisterDevice(String fcmToken) async {
    final response = await _apiClient.delete<Map<String, dynamic>>(
      ApiEndpoints.registerDevice,
      data: {'fcmToken': fcmToken},
    );
    unwrapOrThrow(response.statusCode, response.data);
  }
}
