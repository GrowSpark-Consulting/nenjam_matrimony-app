import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/permissions/permission_providers.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../data/repositories/notification_api_repository_impl.dart';
import '../../data/services/local_notification_service.dart';
import '../../data/services/push_notification_service.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notification_repository.dart';
import '../services/notification_navigation_service.dart';

/// Real backend, live against the `notifications` module (GET /notifications,
/// GET /notifications/unread-count, PATCH /:id/read, PATCH /read-all). Swapped
/// from the dormant mock now that the controller ships — nothing else in this
/// file changed.
final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationApiRepositoryImpl(ref.watch(apiClientProvider)),
);

final localNotificationServiceProvider = Provider<LocalNotificationService>(
  (ref) => LocalNotificationService(),
);

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  // Every tap — system tray (background/terminated) and locally-shown
  // foreground notifications alike — funnels into the same service the
  // in-app Notification Center list uses, so a given notification type can
  // only ever have one destination.
  final navigation = ref.watch(notificationNavigationServiceProvider);
  return PushNotificationService(
    notificationRepository: ref.watch(notificationRepositoryProvider),
    localNotificationService: ref.watch(localNotificationServiceProvider),
    permissionService: ref.watch(appPermissionServiceProvider),
    onNotificationTap: navigation.handle,
  );
});

/// Starts FCM (permission + token registration/refresh + foreground/tap
/// listeners) while signed in, and deactivates the device token on
/// sign-out — mirrors `realtimeSyncProvider`'s auth-reactive lifecycle
/// (`core/realtime/realtime_providers.dart`). Watch this once at the app
/// root (see main.dart).
final pushNotificationSyncProvider = Provider<void>((ref) {
  final service = ref.watch(pushNotificationServiceProvider);
  ref.listen<Object?>(
    currentAuthUserProvider,
    (previous, next) {
      if (next != null) {
        unawaited(service.start());
      } else {
        unawaited(service.stop());
      }
    },
    fireImmediately: true,
  );
});

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
