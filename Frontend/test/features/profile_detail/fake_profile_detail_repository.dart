import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/profile_detail/data/datasources/profile_detail_remote_datasource.dart';
import 'package:nenjam_matrimony/features/profile_detail/domain/entities/profile_detail_entity.dart';
import 'package:nenjam_matrimony/features/profile_detail/domain/repositories/profile_detail_repository.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/providers/profile_detail_providers.dart';

/// Test fixture: answers with a fully filled-in
/// `GET /discover/profiles/:userId` response, run through the real
/// [parseProfileDetail] mapper, so page tests render every section without a
/// network. Test-only — production reads the backend.
class FakeProfileDetailRepository implements ProfileDetailRepository {
  const FakeProfileDetailRepository();

  @override
  Future<ProfileDetailEntity> getProfileDetail(DiscoveryProfileEntity base) =>
      Future.value(
        parseProfileDetail(base, {
          'id': base.id,
          'name': base.name,
          'age': base.age,
          'location': base.location,
          'profession': base.profession,
          'photoUrls': <String>[],
          'isVerified': base.isVerified,
          'phoneVerified': base.phoneVerified,
          'maritalStatus': 'Never Married',
          'motherTongue': 'Tamil',
          'bio': 'Designs homes and reads on weekends.',
          'hobbies': ['Reading', 'Sketching', 'Music', 'Travel'],
          'diet': 'Vegetarian',
          'smoking': 'No',
          'drinking': 'No',
          'physicalStatus': 'Normal',
          'detail': {
            'family': {
              'fatherName': 'Fixture Father',
              'fatherOccupation': 'Teacher',
              'motherName': 'Fixture Mother',
              'motherOccupation': 'Homemaker',
              'familyType': 'Nuclear',
              'familyValues': 'Moderate',
              'familyStatus': 'Middle Class',
              'brothers': 1,
              'sisters': 1,
            },
            'fitness': 'Regularly',
            'horoscope': {
              'rasi': 'Simha',
              'nakshatra': 'Magha',
              'dosham': '',
              'horoscopeAvailable': true,
            },
            'partnerPreference': {
              'minAge': 27,
              'maxAge': 33,
              'minHeightCm': 152,
              'maxHeightCm': 180,
              'religions': ['Hindu'],
              'education': ['Any Degree'],
              'states': ['Tamil Nadu'],
              'maritalStatuses': ['Never Married'],
            },
          },
        }),
      );
}

final fakeProfileDetailOverride = profileDetailRepositoryProvider
    .overrideWithValue(const FakeProfileDetailRepository());
