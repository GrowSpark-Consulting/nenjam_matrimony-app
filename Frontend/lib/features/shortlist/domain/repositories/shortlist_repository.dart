import '../../../discover/domain/entities/discovery_profile_entity.dart';

/// Pure abstract Dart interface. Concrete implementations live in `data/`:
/// [MockShortlistRepository] (in-memory, mutable — what's actually wired
/// via `shortlistRepositoryProvider` today) and [ShortlistRepositoryImpl]
/// (dormant real HTTP implementation, ready for when the backend's
/// `matches`/shortlist routes ship — the `Shortlist` Prisma model is
/// already live in the DB, only the NestJS controller is an empty stub).
abstract interface class ShortlistRepository {
  /// `GET /matches/shortlist` — the same path [add] POSTs to, listing
  /// rather than adding (a common REST convention: one resource path, verb
  /// picks the action).
  Future<List<DiscoveryProfileEntity>> getShortlisted({
    int page = 1,
    int limit = 20,
  });

  /// `POST /matches/shortlist` — adds a profile to the current user's
  /// shortlist. Mirrors the backend's `@@unique([userId, targetUserId])`
  /// constraint: adding an already-shortlisted profile is a no-op, never a
  /// second record.
  Future<void> add(DiscoveryProfileEntity profile);

  /// `DELETE /matches/shortlist` (proposed — backend `matches` controller
  /// is currently an empty stub, so the removal verb/shape isn't confirmed
  /// yet).
  Future<void> remove(String profileId);
}
