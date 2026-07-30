import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows a heads-up notification for FCM messages that arrive while the app
/// is in the foreground. Android/iOS only auto-display a system-tray
/// notification for background/terminated delivery — a foreground message
/// needs an explicit local notification to get the same visible treatment.
class LocalNotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'nenjam_default_channel',
    'Notifications',
    description: 'Interests, matches, messages, and account updates.',
    importance: Importance.high,
  );

  /// Registers the Android notification channel and the tap callback for
  /// locally-shown notifications (foreground FCM messages only — taps on the
  /// OS-rendered background/terminated notification instead go through
  /// `FirebaseMessaging.onMessageOpenedApp`/`getInitialMessage`, handled by
  /// `PushNotificationService`). Safe to call more than once.
  Future<void> initialize({
    required void Function(Map<String, dynamic> data) onTap,
  }) async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) onTap(decoded);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// Displays [message] as a local heads-up notification. A no-op if the
  /// message has no `notification` block (a silent/data-only push).
  Future<void> show(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _plugin.show(
      id: _notificationId(message),
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// A stable id for [message] so a redelivered FCM message (network retry,
  /// duplicate send) replaces the existing tray notification instead of
  /// showing a second one — `RemoteMessage`/`RemoteNotification` don't
  /// override `hashCode`, so it's identity-based per Dart object instance
  /// and would differ across redeliveries of the "same" message. FCM's own
  /// `messageId` is stable per send, so it's the correct dedup key; falling
  /// back to the notification's own hashCode only for the rare case a
  /// message arrives with no `messageId` (e.g. certain locally-constructed
  /// test messages).
  int _notificationId(RemoteMessage message) =>
      message.messageId?.hashCode ?? message.notification.hashCode;
}
