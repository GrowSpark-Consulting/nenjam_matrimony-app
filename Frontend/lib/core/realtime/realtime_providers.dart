import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bootstrap.dart';
import '../../features/authentication/presentation/providers/auth_providers.dart';
import '../../features/interests/presentation/providers/interests_provider.dart';
import '../../features/notifications/presentation/providers/notification_providers.dart';
import '../../features/shortlist/presentation/providers/shortlist_provider.dart';
import 'realtime_event.dart';
import 'realtime_service.dart';

/// The single [RealtimeService] for the app, tokened by the signed-in user's
/// Firebase ID token (the same token the REST client uses).
final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final tokenService = ref.watch(authTokenServiceProvider);
  final service = RealtimeService(
    baseUrl: appConfig.envConfig.apiBaseUrl,
    tokenProvider: () => tokenService.getFirebaseToken(),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Wires the socket lifecycle to auth state and turns inbound events into
/// **targeted** provider invalidations. Watch this once at the app root
/// (see main.dart) so it lives for the whole session.
///
/// Invalidating an `AsyncNotifierProvider` re-runs only that provider's
/// `build()` (a fresh REST fetch) and rebuilds only the widgets watching it —
/// unrelated screens never rebuild. Because each event just triggers an
/// idempotent re-fetch, duplicates from reconnect/resume/push are harmless.
final realtimeSyncProvider = Provider<void>((ref) {
  final service = ref.watch(realtimeServiceProvider);

  // Connect while signed in; disconnect on sign-out. `fireImmediately` handles
  // the already-signed-in cold start.
  ref.listen<Object?>(
    currentAuthUserProvider,
    (previous, next) {
      if (next != null) {
        service.connect();
      } else {
        service.disconnect();
      }
    },
    fireImmediately: true,
  );

  final subscription = service.events.listen((event) {
    switch (event) {
      case RealtimeEvent.interestCreated:
      case RealtimeEvent.interestAccepted:
      case RealtimeEvent.interestRejected:
        ref.invalidate(interestsNotifierProvider);
        ref.invalidate(notificationsNotifierProvider);
      case RealtimeEvent.shortlistCreated:
        ref.invalidate(shortlistNotifierProvider);
        ref.invalidate(notificationsNotifierProvider);
      case RealtimeEvent.notificationCreated:
        ref.invalidate(notificationsNotifierProvider);
    }
  });
  ref.onDispose(subscription.cancel);
});
