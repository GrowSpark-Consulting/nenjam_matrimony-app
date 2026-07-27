import 'package:permission_handler/permission_handler.dart' as ph;

import 'nm_permission.dart';

/// Centralized runtime-permission gateway.
///
/// Every feature that needs Camera or Notification access goes through this
/// service instead of calling `permission_handler` directly — that keeps
/// platform-specific permission logic out of widgets and makes the
/// permission behavior mockable in tests (see [AppPermissionService] as the
/// injectable seam; [AppPermissionServiceImpl] is the only place that talks
/// to the OS).
///
/// Gallery/photo access is intentionally NOT modeled here: `image_picker`
/// opens the system photo picker (Android Photo Picker / iOS
/// `PHPickerViewController`), which grants access to only the photo(s) the
/// user selects and requires no runtime permission on modern OS versions.
/// Requesting `READ_MEDIA_IMAGES`/`Photos` broad-library access for that
/// would be exactly the obsolete, unnecessary permission this task calls
/// out to avoid.
abstract class AppPermissionService {
  /// Current status without prompting the user.
  Future<NmPermissionStatus> statusOf(NmPermission permission);

  /// Shows the OS permission prompt. Safe to call even when already
  /// permanently denied (the OS will simply not show a dialog again) — but
  /// callers should check [statusOf] first so they can offer "Open
  /// Settings" instead of a silent no-op.
  Future<NmPermissionStatus> request(NmPermission permission);

  /// Opens the app's OS settings screen. Returns whether the settings
  /// screen could be opened.
  Future<bool> openSettings();
}

class AppPermissionServiceImpl implements AppPermissionService {
  const AppPermissionServiceImpl();

  ph.Permission _map(NmPermission permission) => switch (permission) {
    NmPermission.camera => ph.Permission.camera,
    NmPermission.notification => ph.Permission.notification,
    NmPermission.microphone => ph.Permission.microphone,
  };

  NmPermissionStatus _mapStatus(ph.PermissionStatus status) => switch (status) {
    ph.PermissionStatus.granted => NmPermissionStatus.granted,
    ph.PermissionStatus.denied => NmPermissionStatus.denied,
    ph.PermissionStatus.restricted => NmPermissionStatus.restricted,
    ph.PermissionStatus.limited => NmPermissionStatus.limited,
    ph.PermissionStatus.permanentlyDenied =>
      NmPermissionStatus.permanentlyDenied,
    ph.PermissionStatus.provisional => NmPermissionStatus.provisional,
  };

  @override
  Future<NmPermissionStatus> statusOf(NmPermission permission) async {
    final status = await _map(permission).status;
    return _mapStatus(status);
  }

  @override
  Future<NmPermissionStatus> request(NmPermission permission) async {
    final status = await _map(permission).request();
    return _mapStatus(status);
  }

  @override
  Future<bool> openSettings() => ph.openAppSettings();
}
