import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_permission_service.dart';
import 'nm_permission.dart';

/// Overridable in tests with a fake [AppPermissionService].
final appPermissionServiceProvider = Provider<AppPermissionService>(
  (ref) => const AppPermissionServiceImpl(),
);

/// Current notification permission status — watched by the Settings page
/// toggle. Call `ref.invalidate(notificationPermissionStatusProvider)`
/// after any action that may have changed it (request, return from Settings).
final notificationPermissionStatusProvider = FutureProvider<NmPermissionStatus>(
  (ref) => ref
      .watch(appPermissionServiceProvider)
      .statusOf(NmPermission.notification),
);
