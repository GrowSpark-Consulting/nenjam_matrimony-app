import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/notification_api_repository_impl.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notification_repository.dart';

/// Real backend, live against the `notifications` module (GET /notifications,
/// GET /notifications/unread-count, PATCH /:id/read, PATCH /read-all). Swapped
/// from the dormant mock now that the controller ships — nothing else in this
/// file changed.
final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationApiRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Owns the notifications list — every mutation (tapping an unread card,
/// "Mark all as read") goes through this notifier so the in-memory
/// repository and the UI (including the Discover bell badge) never disagree
/// about current state.
class NotificationsNotifier extends AsyncNotifier<List<NotificationEntity>> {
  @override
  Future<List<NotificationEntity>> build() async {
    final page = await ref.watch(notificationRepositoryProvider).getNotifications();
    return page.items;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final page = await ref.read(notificationRepositoryProvider).getNotifications();
      return page.items;
    });
  }

  Future<void> markRead(String id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final alreadyRead = current.any((n) => n.id == id && n.isRead);
    if (alreadyRead) return;
    state = AsyncValue.data([
      for (final n in current) if (n.id == id) n.copyWith(isRead: true) else n,
    ]);
    await ref.read(notificationRepositoryProvider).markRead(id);
  }

  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([for (final n in current) n.copyWith(isRead: true)]);
    await ref.read(notificationRepositoryProvider).markAllRead();
  }
}

final notificationsNotifierProvider =
    AsyncNotifierProvider<NotificationsNotifier, List<NotificationEntity>>(
  NotificationsNotifier.new,
);

/// Unread count for the Discover bell badge — derived from the same list
/// the Notification page shows, so the two can never disagree.
final unreadNotificationsCountProvider = Provider<int>((ref) {
  final all = ref.watch(notificationsNotifierProvider).valueOrNull ?? const [];
  return all.where((n) => !n.isRead).length;
});
