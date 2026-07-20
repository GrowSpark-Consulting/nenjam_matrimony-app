import '../../../discover/domain/entities/discovery_profile_entity.dart';

/// Pure abstract Dart interface. Concrete implementation lives in `data/`.
/// Not wired to any provider today — `shortlisted_page.dart` is a static
/// "Coming Soon" screen.
abstract interface class ShortlistRepository {
  /// `GET /matches/shortlist` — same path `MatchesRepository.shortlist()`
  /// POSTs to, listing rather than adding (a common REST convention: one
  /// resource path, verb picks the action).
  Future<List<DiscoveryProfileEntity>> getShortlisted({
    int page = 1,
    int limit = 20,
  });

  /// `DELETE /matches/shortlist` (proposed — backend `matches` controller
  /// is currently an empty stub, so the removal verb/shape isn't confirmed
  /// yet).
  Future<void> remove(String profileId);
}
