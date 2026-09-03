/// Permissions Nenjam actually requests at runtime.
///
/// Deliberately does NOT include photos/gallery (the system photo picker on
/// both platforms needs no runtime permission — see [AppPermissionService]
/// doc comment). Microphone was added once Chat's voice-message recording
/// became real — see `features/inbox/presentation/widgets/chat_composer.dart`.
///
/// Location is also absent, but for a different reason than it used to be:
/// Near Me is now a real GPS feature (`core/services/location/`), it simply
/// does not route through `permission_handler`. `DeviceLocationService` asks
/// geolocator instead, because there the permission request and the position
/// fix are one operation — and because geolocator alone can distinguish two
/// failures that need different fixes from the user: permission denied, versus
/// location SERVICES switched off device-wide. Modelling it here as well would
/// leave two packages answering the same question, free to disagree. The one
/// piece Near Me does reuse from here is [AppPermissionService.openSettings],
/// for the permanently-denied case.
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
