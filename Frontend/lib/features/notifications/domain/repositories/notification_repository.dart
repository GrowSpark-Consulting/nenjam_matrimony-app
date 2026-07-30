import '../entities/notification_entity.dart';

/// A single page of the notifications list — mirrors
/// `features/inbox/domain/repositories/conversation_repository.dart`'s
/// `ConversationResultPage` shape for consistency across list features, and
/// keeps the repository cursor/page-ready without the UI needing infinite
/// scroll yet.
class NotificationResultPage {
  const NotificationResultPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  final List<NotificationEntity> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;
}

/// Pure abstract Dart interface. Concrete implementations live in `data/`:
/// [NotificationRepositoryImpl] (in-memory, mock-backed — what's actually
/// wired via `notificationRepositoryProvider` today, since the backend's
/// `notifications` module is scaffolded but empty/unwired — see
/// `backend/apps/api/src/modules/notifications/`) and
/// [NotificationApiRepositoryImpl] (dormant, hits `ApiEndpoints.notifications`
/// — the swap-in once that controller ships).
abstract interface class NotificationRepository {
  Future<NotificationResultPage> getNotifications({int page = 1, int limit = 20});

  Future<int> getUnreadCount();

  Future<void> markRead(String id);

  Future<void> markAllRead();

  /// Registers (or reactivates) this device's FCM token with the backend so
  /// it starts receiving push notifications. `platform` is `'ANDROID'` or
  /// `'IOS'`, matching the backend's `DevicePlatform` enum.
  Future<void> registerDevice({required String fcmToken, required String platform});

  /// Deactivates this device's FCM token — called on sign-out so a
  /// signed-out device stops receiving pushes meant for the account that
  /// just logged out.
  Future<void> unregisterDevice(String fcmToken);
}
