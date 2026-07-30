import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/router/route_names.dart';
import '../../domain/entities/notification_entity.dart';

/// Routes a push-notification tap (background, terminated, or a
/// locally-shown foreground notification) to the correct screen.
///
/// Only covers destinations reachable with no extra data — the same
/// constraint [NotificationsPage]'s own in-app tap handler is built around —
/// and falls back to the Notification Center for every other type rather
/// than guessing a route. Uses [rootNavigatorKey] because a push tap can
/// arrive with no [BuildContext] of its own (app cold-starting from
/// terminated).
void navigateForNotificationData(Map<String, dynamic> data) {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;

  final type = NotificationType.fromBackendValue(data['type'] as String?);
  final route = switch (type) {
    NotificationType.profileCompletionReminder => RouteNames.profileCompletion,
    NotificationType.verificationUpdate => RouteNames.verification,
    _ => RouteNames.notifications,
  };
  context.push(route);
}
