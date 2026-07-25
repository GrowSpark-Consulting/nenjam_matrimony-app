import '../../../../core/network/api_exception.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/repositories/shortlist_repository.dart';

/// In-memory mock — no network calls. Holds the shortlisted list as the
/// single source of truth in memory (same "cache + mutate" approach as
/// `MockInterestsRepository`/`ConversationRepositoryImpl`) so `add`/`remove`
/// are immediately reflected the next time [getShortlisted] is called — the
/// notifier never needs its own parallel copy of this state. Default
/// implementation until the backend `matches`/shortlist routes ship (see
/// [ShortlistRepositoryImpl], which already targets the proposed endpoints
/// but has nothing live to call yet).
///
/// Starts empty — unlike Interests' mock (which seeds a few demo records so
/// the Inbox tabs have something to show immediately), a shortlist is a
/// private saved list with nothing worth pre-seeding; it fills up purely
/// from the user's own actions during the session.
class MockShortlistRepository implements ShortlistRepository {
  final List<DiscoveryProfileEntity> _shortlisted = [];

  @override
  Future<List<DiscoveryProfileEntity>> getShortlisted({
    int page = 1,
    int limit = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_shortlisted);
  }

  @override
  Future<void> add(DiscoveryProfileEntity profile) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Mirrors the backend's @@unique([userId, targetUserId]) — adding an
    // already-shortlisted profile again must never create a duplicate.
    if (_shortlisted.any((p) => p.id == profile.id)) return;
    _shortlisted.add(profile);
  }

  @override
  Future<void> remove(String profileId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final existed = _shortlisted.any((p) => p.id == profileId);
    if (!existed) {
      // Mirrors a backend 404 for removing a non-existent row — surfaced so
      // the notifier's rollback path has something real to guard against,
      // even though the UI should never actually hit this (buttons only
      // ever call remove for a profile the shared state already says is
      // shortlisted).
      throw ApiException(404, 'Profile is not in your shortlist.');
    }
    _shortlisted.removeWhere((p) => p.id == profileId);
  }
}
