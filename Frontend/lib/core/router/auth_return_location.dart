import 'route_names.dart';

/// Where a signed-out visitor was headed when the router guard sent them to
/// the landing screen — a shared profile link, a bookmarked chat, a reload
/// after the session lapsed — so logging in can finish the trip instead of
/// always ending on Discover.
///
/// Held in memory only: on the web the guard's bounce and the login that
/// follows happen in the same page load, and a remembered link must never
/// outlive the visit that asked for it.
abstract final class AuthReturnLocation {
  static String? _pending;

  /// The remembered location, if any. For tests and diagnostics.
  static String? get pending => _pending;

  static void remember(String location) {
    // Only an in-app path; a public route is somewhere the visitor can
    // already go, so there is nothing to return to.
    if (!location.startsWith('/') || location.startsWith('//')) return;
    final path = Uri.parse(location).path;
    if (RouteNames.publicRoutes.contains(path)) return;
    _pending = location;
  }

  static void clear() => _pending = null;

  /// What a login should navigate to, given [resolved] — the answer from
  /// `PostAuthDestination` (or Discover, for logins that cannot ask it).
  ///
  /// Only Discover, which means "registration is finished", is replaced by
  /// the remembered location; an onboarding step the account still owes
  /// always wins. The location is consumed either way, so it is used once.
  static String afterLogin(String resolved) {
    final pending = _pending;
    _pending = null;
    if (resolved == RouteNames.discover && pending != null) return pending;
    return resolved;
  }
}
