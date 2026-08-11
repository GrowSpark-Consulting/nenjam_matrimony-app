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
      onDidReceiveNotificationResponse: (response) =>
          _dispatchPayload(response.payload, onTap),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // A notification this app rendered itself (i.e. one shown while the app
    // was in the foreground) stays in the tray after the process is killed.
    // Tapping it then cold-starts the app, and neither
    // `onDidReceiveNotificationResponse` nor FCM's `getInitialMessage()`
    // fires for it — `getNotificationAppLaunchDetails` is the only way that
    // tap is ever observed, so without this the deep link is silently lost.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _dispatchPayload(launch!.notificationResponse?.payload, onTap);
    }
  }

  void _dispatchPayload(
    String? payload,
    void Function(Map<String, dynamic> data) onTap,
  ) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) onTap(decoded);
    } on FormatException {
      // A malformed payload must never take down the tap handler (or, via
      // initialize(), the whole push setup).
    }
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
      // The delivery id rides along so a tap on this notification
      // deduplicates against the same message arriving through FCM's own tap
      // callbacks (see PushNotificationService._tapData).
      payload: jsonEncode({
        ...message.data,
        if (message.messageId != null) 'deliveryId': message.messageId!,
      }),
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
