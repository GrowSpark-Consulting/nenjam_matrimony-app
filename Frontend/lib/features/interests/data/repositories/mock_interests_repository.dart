import '../../../../core/network/api_exception.dart';
import '../../../discover/domain/entities/compatibility_entity.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/repositories/interests_repository.dart';

/// In-memory mock — no network calls. Holds the seeded lists as the single
/// source of truth in memory (same "cache + mutate" approach as
/// `features/inbox/data/repositories/conversation_repository_impl.dart` and
/// `features/notifications/data/repositories/notification_repository_impl.dart`)
/// so `sendInterest`/`respond`/`withdraw` are immediately reflected the next
/// time [getReceived]/[getSent] is called — the notifier never needs its own
/// parallel copy of this state. Default implementation until the
/// `interests` backend controller ships real routes (see
/// [InterestsRepositoryImpl], which already targets the proposed endpoints
/// but has nothing live to call yet).
class MockInterestsRepository implements InterestsRepository {
  List<InterestRecord>? _received;
  List<InterestRecord>? _sent;
  int _nextSentId = 100;

  DiscoveryProfileEntity _profile({
    required String id,
    required String name,
    required String gender,
    required int age,
    required String location,
    required String profession,
    int aiMatchPercent = 0,
    bool isVerified = false,
    bool isPremium = false,
  }) {
    return DiscoveryProfileEntity(
      id: id,
      matrimonyId: 'NM1002${id.padLeft(2, '5')}',
      name: name,
      gender: gender,
      age: age,
      location: location,
      profession: profession,
      education: '',
      photoUrls: const [],
      isVerified: isVerified,
      isPremium: isPremium,
      compatibility: CompatibilityEntity(
        aiMatchPercent: aiMatchPercent,
        overallCompatibility: aiMatchPercent,
      ),
    );
  }

  List<InterestRecord> _seedReceived() {
    final now = DateTime.now();
    return [
      InterestRecord(
        id: 'ir1',
        profile: _profile(
          id: '90', name: 'Nithya Balan', gender: 'Female', age: 27,
          location: 'Chennai', profession: 'Lawyer', aiMatchPercent: 86, isVerified: true,
        ),
        sentAt: now.subtract(const Duration(hours: 5)),
        status: InterestStatus.pending,
      ),
      InterestRecord(
        id: 'ir2',
        profile: _profile(
          id: '91', name: 'Praveen Kumar', gender: 'Male', age: 30,
          location: 'Bengaluru', profession: 'Consultant', aiMatchPercent: 74, isPremium: true,
        ),
        sentAt: now.subtract(const Duration(days: 1)),
        status: InterestStatus.pending,
      ),
      InterestRecord(
        id: 'ir3',
        profile: _profile(
          id: '92', name: 'Swathi Reddy', gender: 'Female', age: 26,
          location: 'Hyderabad', profession: 'Dentist', aiMatchPercent: 91, isVerified: true,
        ),
        sentAt: now.subtract(const Duration(days: 2)),
        status: InterestStatus.accepted,
      ),
    ];
  }

  List<InterestRecord> _seedSent() {
    final now = DateTime.now();
    return [
      InterestRecord(
        id: 'is1',
        profile: _profile(
          id: '93', name: 'Aravind Selvam', gender: 'Male', age: 31,
          location: 'Coimbatore', profession: 'Architect', aiMatchPercent: 82,
        ),
        sentAt: now.subtract(const Duration(hours: 10)),
        status: InterestStatus.pending,
      ),
      InterestRecord(
        id: 'is2',
        profile: _profile(
          id: '94', name: 'Harini Prakash', gender: 'Female', age: 28,
          location: 'Madurai', profession: 'Professor', aiMatchPercent: 69, isVerified: true,
        ),
        sentAt: now.subtract(const Duration(days: 3)),
        status: InterestStatus.declined,
      ),
    ];
  }

  @override
  Future<List<InterestRecord>> getReceived({int page = 1, int limit = 20}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_received ??= _seedReceived());
  }

  @override
  Future<List<InterestRecord>> getSent({int page = 1, int limit = 20}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_sent ??= _seedSent());
  }

  @override
  Future<InterestRecord> sendInterest(DiscoveryProfileEntity profile) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final sent = _sent ??= _seedSent();
    final received = _received ??= _seedReceived();

    // Mirrors the backend's @@unique([senderId, receiverId]) — refuse a
    // second active interest in either direction for the same pair.
    final alreadyActive = sent.any((r) =>
            r.profile.id == profile.id && r.status != InterestStatus.declined) ||
        received.any((r) =>
            r.profile.id == profile.id && r.status != InterestStatus.declined);
    if (alreadyActive) {
      throw ApiException(409, 'You have already expressed interest with this profile.');
    }

    final record = InterestRecord(
      id: 'is-mock-${_nextSentId++}',
      profile: profile,
      sentAt: DateTime.now(),
      status: InterestStatus.pending,
    );
    _sent = [record, ...sent];
    return record;
  }

  @override
  Future<void> respond(String interestId, {required bool accept}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final received = _received ??= _seedReceived();
    _received = [
      for (final r in received)
        if (r.id == interestId)
          r.copyWith(status: accept ? InterestStatus.accepted : InterestStatus.declined)
        else
          r,
    ];
  }

  @override
  Future<void> withdraw(String interestId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final sent = _sent ??= _seedSent();
    _sent = sent.where((r) => r.id != interestId).toList();
  }
}
