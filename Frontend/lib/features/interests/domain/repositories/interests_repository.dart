import '../../../discover/domain/entities/discovery_profile_entity.dart';

/// A single "interest" — someone expressing interest in a profile, in
/// either direction. Mirrors the backend's `ExpressInterest` Prisma model
/// (`senderId, receiverId, status, createdAt, respondedAt` — see
/// `backend/libs/database/prisma/schema.prisma`).
class InterestRecord {
  const InterestRecord({
    required this.id,
    required this.profile,
    required this.sentAt,
    required this.status,
  });

  final String id;
  final DiscoveryProfileEntity profile;
  final DateTime sentAt;
  final InterestStatus status;

  InterestRecord copyWith({InterestStatus? status}) => InterestRecord(
        id: id,
        profile: profile,
        sentAt: sentAt,
        status: status ?? this.status,
      );
}

/// Status of a single interest record — matches the backend's
/// `InterestStatus` Prisma enum (`PENDING`/`ACCEPTED`/`DECLINED`) exactly.
/// There is deliberately no "withdrawn"/"cancelled" value here: the backend
/// has no such status, a withdrawn interest is simply deleted (see
/// [InterestsRepository.withdraw]), so a record either exists with one of
/// these three statuses or doesn't exist at all.
enum InterestStatus { pending, accepted, declined }

/// The current user's *relationship* with a given profile — distinct from
/// [InterestStatus], which describes one record. This is what every "Send
/// Interest" button across Discover/Matches/Profile Detail actually reads,
/// so they can never show "Send Interest" to someone already
/// sent/received/accepted. [cancelled] is part of the conceptual model but
/// is never produced by [deriveRelationshipStatus] today — withdrawing
/// removes the record outright and the relationship goes straight back to
/// [none] (matching how the backend represents a withdrawal), so [cancelled]
/// is reserved for a future "just withdrew" transient UI moment rather than
/// a persisted state.
enum InterestRelationshipStatus { none, sent, received, accepted, declined, cancelled }

/// Pure function, no provider/state dependency — scans both lists once to
/// answer "what is my relationship with this profile", so every screen
/// derives the exact same answer from the exact same two lists rather than
/// keeping its own parallel boolean.
InterestRelationshipStatus deriveRelationshipStatus({
  required String profileId,
  required List<InterestRecord> sent,
  required List<InterestRecord> received,
}) {
  for (final record in received) {
    if (record.profile.id != profileId) continue;
    switch (record.status) {
      case InterestStatus.pending:
        return InterestRelationshipStatus.received;
      case InterestStatus.accepted:
        return InterestRelationshipStatus.accepted;
      case InterestStatus.declined:
        return InterestRelationshipStatus.declined;
    }
  }
  for (final record in sent) {
    if (record.profile.id != profileId) continue;
    switch (record.status) {
      case InterestStatus.pending:
        return InterestRelationshipStatus.sent;
      case InterestStatus.accepted:
        return InterestRelationshipStatus.accepted;
      case InterestStatus.declined:
        return InterestRelationshipStatus.declined;
    }
  }
  return InterestRelationshipStatus.none;
}

/// Pure abstract Dart interface. Concrete implementations live in `data/`:
/// [MockInterestsRepository] (in-memory, mutable — what's actually wired via
/// `interestsRepositoryProvider` today) and [InterestsRepositoryImpl]
/// (dormant real HTTP implementation, ready for when the backend `interests`
/// controller ships routes).
abstract interface class InterestsRepository {
  /// `GET /interests/received` (proposed — path not yet confirmed with
  /// backend, the `interests` module is an empty stub).
  Future<List<InterestRecord>> getReceived({int page = 1, int limit = 20});

  /// `GET /interests/sent` (proposed).
  Future<List<InterestRecord>> getSent({int page = 1, int limit = 20});

  /// `POST /matches/interest` — reuses the same write endpoint
  /// `MatchesRepository.expressInterest` already targets rather than
  /// inventing a second one, since both are "create an interest" actions.
  /// Throws if an active (non-declined) interest already exists between
  /// this pair in either direction — mirrors the backend's
  /// `@@unique([senderId, receiverId])` constraint.
  Future<InterestRecord> sendInterest(DiscoveryProfileEntity profile);

  /// `POST /matches/interest` with an accept/decline action — reuses the
  /// same write endpoint Matches already targets rather than inventing a
  /// second one, since both are "respond to an interest" actions.
  Future<void> respond(String interestId, {required bool accept});

  /// `DELETE /interests/:interestId` (proposed) — withdraws a pending SENT
  /// interest. Only ever called for the sender's own pending records; there
  /// is no "unmatch"/remove-connection concept here.
  Future<void> withdraw(String interestId);
}
