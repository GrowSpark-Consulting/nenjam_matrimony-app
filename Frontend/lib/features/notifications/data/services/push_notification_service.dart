import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/permissions/app_permission_service.dart';
import '../../../../core/permissions/nm_permission.dart';
import '../../../../firebase_options.dart';
import '../../domain/repositories/notification_repository.dart';
import 'local_notification_service.dart';

/// Runs in a separate background isolate whenever a push arrives while the
/// app is backgrounded or terminated — that isolate never ran `main()`, so
/// Firebase must be re-initialized here (FlutterFire's documented pattern).
/// No Riverpod/ProviderScope access exists in this isolate, so this stays
/// minimal: every push payload already carries a `notification` block (see
/// backend `PushDispatchService`), which Android/iOS auto-display in the
/// system tray with no further action needed here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Wires Firebase Cloud Messaging end-to-end: permission request, FCM token
/// registration/refresh with the backend, and foreground/tap/terminated
/// message handling. Owned by `pushNotificationSyncProvider`
/// (`presentation/providers/notification_providers.dart`), which calls
/// [start]/[stop] as the signed-in session begins/ends, and by
/// `main.dart`'s app-resume hook, which calls [checkPermissionOnResume].
///
/// [start], [stop], and [checkPermissionOnResume] are all funneled through
/// [_enqueue], a simple chained-Future mutex — the auth-state listener that
/// drives [start]/[stop] fires `unawaited(...)`, so a rapid sign-in
/// immediately followed by a sign-out (e.g. a stale session bounced by
/// `_checkSessionOnResume` right after restore) would otherwise let the two
/// calls' async steps interleave: `stop()` could cancel subscriptions that
/// don't exist yet while `start()` is still mid-flight, and `start()` could
/// then attach listeners / re-register the token *after* `stop()` already
/// ran — for a session that's already signed out. Queuing forces every call
/// to run to completion, strictly in invocation order, before the next one
/// starts, so the final state always matches the last auth event with no
/// interleaving possible.
class PushNotificationService {
  PushNotificationService({
    required NotificationRepository notificationRepository,
    required LocalNotificationService localNotificationService,
    required AppPermissionService permissionService,
    required void Function(Map<String, dynamic> data) onNotificationTap,
  }) : _notificationRepository = notificationRepository,
       _localNotificationService = localNotificationService,
       _permissionService = permissionService,
       _onNotificationTap = onNotificationTap;

  final NotificationRepository _notificationRepository;
  final LocalNotificationService _localNotificationService;
  final AppPermissionService _permissionService;
  final void Function(Map<String, dynamic> data) _onNotificationTap;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  /// Whether a signed-in session is currently active (set in [_doStart],
  /// cleared in [_doStop]) — distinct from [_listenersAttached] because a
  /// session can be "active" while notification permission is still denied,
  /// in which case listeners are deliberately not attached yet.
  bool _started = false;

  /// Whether FCM listeners are attached and the token is registered.
  /// Permission can be denied when [_doStart] first runs (leaving this
  /// `false` for the rest of that session) and later granted from Android
  /// Settings — [checkPermissionOnResume] is what completes the setup at
  /// that point, without needing a fresh [start] (i.e. a logout/login).
  bool _listenersAttached = false;

  /// Tail of the operation chain — see the class doc comment.
  Future<void> _queue = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _queue.then((_) => operation());
    // The queue's own tail must never carry an error forward (that would
    // permanently wedge every later enqueued operation) — the caller of
    // start()/stop()/checkPermissionOnResume still sees [result]'s own
    // success/failure normally.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Requests notification permission, registers the current device token,
  /// and starts listening for foreground/tap/refresh events. Safe to call
  /// repeatedly — a session that's already fully started, or already denied
  /// permission this session, is a no-op until [stop] resets it.
  Future<void> start() => _enqueue(_doStart);

  /// Deactivates this device's token on the backend and tears down
  /// listeners — called on sign-out so a signed-out device stops receiving
  /// pushes meant for the account that just logged out.
  Future<void> stop() => _enqueue(_doStop);

  /// Re-checks notification permission without prompting (no OS dialog) and
  /// finishes registration if it's now granted. Call this on every app
  /// resume (see `main.dart`) — a user who denied the prompt on first launch
  /// and later enabled notifications from Android Settings gets registered
  /// the moment they come back to the app, with no logout/login needed.
  Future<void> checkPermissionOnResume() => _enqueue(_doCheckPermissionOnResume);

  Future<void> _doStart() async {
    if (kIsWeb) return;
    _started = true;
    if (_listenersAttached) return;

    await _localNotificationService.initialize(onTap: _onNotificationTap);

    final status = await _permissionService.request(NmPermission.notification);
    if (!status.isGranted) return;

    await _attachListenersAndRegister();
  }

  Future<void> _doStop() async {
    await _tokenRefreshSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedAppSub?.cancel();
    _tokenRefreshSub = null;
    _foregroundSub = null;
    _openedAppSub = null;

    final wasListening = _listenersAttached;
    _started = false;
    _listenersAttached = false;
    if (kIsWeb || !wasListening) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _notificationRepository.unregisterDevice(token);
      }
    } catch (_) {
      // Best-effort — a failed unregister just leaves a stale token, which
      // the backend deactivates itself the next time a push to it bounces.
    }
  }

  Future<void> _doCheckPermissionOnResume() async {
    // Nothing to do if there's no active session, or it's already fully
    // wired — this runs on every resume, so it must stay cheap in the
    // common case.
    if (kIsWeb || !_started || _listenersAttached) return;

    final status = await _permissionService.statusOf(NmPermission.notification);
    if (!status.isGranted) return;

    await _attachListenersAndRegister();
  }

  /// Registers the token and attaches the FCM listeners exactly once per
  /// session — shared by [_doStart] (permission already granted) and
  /// [_doCheckPermissionOnResume] (permission granted after the fact).
  Future<void> _attachListenersAndRegister() async {
    if (_listenersAttached) return;
    _listenersAttached = true;

    await _registerCurrentToken();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => _registerCurrentToken(),
    );

    _foregroundSub = FirebaseMessaging.onMessage.listen(_showForegroundMessage);
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _onNotificationTap(message.data),
    );

    // The app was launched by tapping a notification while fully
    // terminated — onMessageOpenedApp never fires for that case.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _onNotificationTap(initialMessage.data);
    }
  }

  Future<void> _registerCurrentToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _notificationRepository.registerDevice(
        fcmToken: token,
        platform: _platformWire,
      );
    } catch (_) {
      // Best-effort — never blocks app usage over a push-registration
      // failure (offline, backend hiccup, ...).
    }
  }

  void _showForegroundMessage(RemoteMessage message) {
    unawaited(_localNotificationService.show(message));
  }

  String get _platformWire =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';
}
