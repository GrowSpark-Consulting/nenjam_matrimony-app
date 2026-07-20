import '../../../discover/domain/entities/discovery_profile_entity.dart';

/// A single "interest" — someone expressing interest in a profile, in
/// either direction.
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
}

enum InterestStatus { pending, accepted, declined }

/// Pure abstract Dart interface. Concrete implementation lives in `data/`.
/// Not wired to any provider today — `interests_received_page.dart` and
/// `interests_sent_page.dart` are static "Coming Soon" screens.
abstract interface class InterestsRepository {
  /// `GET /interests/received` (proposed — path not yet confirmed with
  /// backend, the `interests` module is an empty stub).
  Future<List<InterestRecord>> getReceived({int page = 1, int limit = 20});

  /// `GET /interests/sent` (proposed).
  Future<List<InterestRecord>> getSent({int page = 1, int limit = 20});

  /// `POST /matches/interest` with an accept/decline action — reuses the
  /// same write endpoint Matches already targets rather than inventing a
  /// second one, since both are "respond to an interest" actions.
  Future<void> respond(String interestId, {required bool accept});
}
