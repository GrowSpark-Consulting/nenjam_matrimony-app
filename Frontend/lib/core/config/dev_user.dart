/// Synthetic signed-in user used only while [AppConfig.devBypassAuth] is on.
///
/// Never touches Firebase — exists purely so bypass-mode screens have a
/// plausible "current user" to render instead of a real session. The
/// authentication feature shapes this into an `AuthUser` at the provider
/// boundary; this file stays dependency-free so `core/` never reaches into
/// `features/`.
abstract final class DevUser {
  static const String id = 'DEV_USER';
  static const String name = 'Dhatri';
  static const bool profileCompleted = true;
  static const bool premium = true;
}
