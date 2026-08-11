import '../entities/profile_viewer_entity.dart';

/// "Who viewed my profile", against
/// `backend/apps/api/src/modules/matches/controllers/matches.controller.ts`.
abstract interface class ProfileViewsRepository {
  /// Distinct viewers of the signed-in user's profile, most recently seen
  /// first (`GET /matches/profile-views`).
  Future<List<ProfileViewerEntity>> getViewers({int page = 1, int limit = 20});

  /// Records that the signed-in user opened [profileId]'s profile
  /// (`POST /matches/profile-view`).
  ///
  /// Fire-and-forget from the caller's perspective: the server logs every
  /// view but only notifies the viewed member once per throttle window, and
  /// a failure here must never interrupt opening a profile.
  Future<void> recordView(String profileId);
}
