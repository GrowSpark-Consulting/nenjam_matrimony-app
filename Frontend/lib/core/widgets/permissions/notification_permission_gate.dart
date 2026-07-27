import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../permissions/nm_permission.dart';
import '../../permissions/permission_providers.dart';
import '../../services/storage_service.dart';
import 'permission_dialogs.dart';

/// Wraps the main app shell (Discover) and — exactly once, the first time
/// the user reaches it — shows Nenjam's own explanation before the OS
/// notification permission popup. Never re-prompts after that, whether the
/// user enabled, said "Not now", or the OS already had a status from
/// elsewhere; permanently-denied is respected silently (no nagging toward
/// Settings on every launch — only the Settings row in the Settings page
/// offers that).
class NotificationPermissionGate extends ConsumerStatefulWidget {
  const NotificationPermissionGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationPermissionGate> createState() =>
      _NotificationPermissionGateState();
}

class _NotificationPermissionGateState
    extends ConsumerState<NotificationPermissionGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  Future<void> _maybePrompt() async {
    if (storageService.hasPromptedNotificationPermission) return;

    final permissions = ref.read(appPermissionServiceProvider);
    final status = await permissions.statusOf(NmPermission.notification);
    // Already decided one way or another (e.g. granted by default on this
    // OS version, or denied via some earlier build before this gate
    // existed) — nothing for Nenjam's own dialog to add.
    if (status != NmPermissionStatus.denied) {
      await storageService.setNotificationPermissionPrompted();
      return;
    }

    if (!mounted) return;
    final enable = await showPermissionPrimerDialog(
      context,
      icon: Icons.notifications_active_rounded,
      title: 'Enable Notifications',
      message:
          'Get notified when someone sends you an interest, accepts your '
          'request, or messages you.',
      proceedLabel: 'Enable',
      cancelLabel: 'Not now',
    );
    await storageService.setNotificationPermissionPrompted();
    if (!enable || !mounted) return;

    final result = await permissions.request(NmPermission.notification);
    ref.invalidate(notificationPermissionStatusProvider);
    if (result == NmPermissionStatus.permanentlyDenied && mounted) {
      await showOpenSettingsDialog(
        context,
        title: 'Notifications Disabled',
        message: 'Enable notifications from Settings to stay updated.',
        onOpenSettings: permissions.openSettings,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
