import '../../../discover/domain/entities/compatibility_entity.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/repositories/interests_repository.dart';

/// In-memory mock — no network calls. Default implementation until the
/// `interests` backend controller ships real routes (see
/// [InterestsRepositoryImpl], which already targets the proposed endpoints
/// but has nothing live to call yet).
class MockInterestsRepository implements InterestsRepository {
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

  @override
  Future<List<InterestRecord>> getReceived({int page = 1, int limit = 20}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
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

  @override
  Future<List<InterestRecord>> getSent({int page = 1, int limit = 20}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
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
  Future<void> respond(String interestId, {required bool accept}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}
