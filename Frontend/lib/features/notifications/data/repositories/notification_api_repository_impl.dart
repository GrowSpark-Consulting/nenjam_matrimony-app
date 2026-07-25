import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/repositories/notification_repository.dart';
import '../models/notification_model.dart';

/// Real backend implementation — dormant, not wired to any provider.
///
/// TODO(backend): `ApiEndpoints.notifications` already exists as a path
/// constant, and the Prisma `Notification` model/migration are already live
/// (`backend/libs/database/prisma/schema.prisma`), but
/// `backend/apps/api/src/modules/notifications/` is an empty scaffold
/// (controller/service/repository/DTO all unimplemented) and isn't imported
/// into `app.module.ts` — so there is no working endpoint to call yet.
/// Proposed shapes once it ships:
///  - `GET {notifications}?page&limit` -> `{ items: [...], page, limit,
///    total, hasMore }`, each item shaped per [NotificationModel.fromJson]
///    (`id, type, title, message|body, isRead, createdAt,
///    actor: { id, name, photoUrl } | null, referenceId, metadata`), `type`
///    being one of the backend's `NotificationType` enum values.
///  - `GET {notifications}/unread-count` -> `{ count: number }`.
///  - `PATCH {notifications}/:id/read` -> marks one notification read.
///  - `PATCH {notifications}/read-all` -> marks every notification read.
///
/// Swap `notificationRepositoryProvider` (notification_providers.dart) from
/// [NotificationRepositoryImpl] to this class once that controller ships —
/// nothing else in the feature needs to change.
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
}
