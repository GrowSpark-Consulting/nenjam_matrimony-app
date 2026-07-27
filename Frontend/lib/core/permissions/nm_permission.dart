/// Permissions Nenjam actually requests at runtime.
///
/// Deliberately does NOT include photos/gallery (the system photo picker on
/// both platforms needs no runtime permission — see [AppPermissionService]
/// doc comment) or location (no GPS-based feature exists — "Near Me" is a
/// backend filter over stored city/state, not device GPS). Microphone was
/// added once Chat's voice-message recording became real — see
/// `features/inbox/presentation/widgets/chat_composer.dart`.
enum NmPermission { camera, notification, microphone }

/// Platform-agnostic permission outcome. Mirrors `permission_handler`'s
/// `PermissionStatus` so the rest of the app never imports that package
/// directly (see [AppPermissionService]).
enum NmPermissionStatus {
  granted,
  denied,
  restricted,
  limited,
  permanentlyDenied,
  provisional;

  bool get isGranted =>
      this == NmPermissionStatus.granted ||
      this == NmPermissionStatus.provisional;
}
