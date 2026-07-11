import '../models/compatibility_result.dart';

/// Relationship Intelligence — Horoscope Matching.
///
/// Fully independent of the registration feature (existing
/// `step_horoscope.dart` in the 12-step wizard is untouched — this covers
/// only the optional matching toggle and compatibility preview).
/// [MockCompatibilityRepository] is wired as the default today; swap the
/// `compatibilityRepositoryProvider` override to [ApiCompatibilityRepository]
/// once the backend team's endpoints are ready.
abstract class CompatibilityRepository {
  Future<HoroscopeSummary> getMyHoroscopeSummary();

  Future<void> setMatchingEnabled(bool enabled);

  /// Compatibility with a specific member, or a representative preview
  /// result when [targetUserId] is omitted (used by the mock for UI
  /// preview purposes).
  Future<CompatibilityResult> getCompatibility({String? targetUserId});
}
