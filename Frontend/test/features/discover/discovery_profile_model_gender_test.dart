import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/data/models/discovery_profile_model.dart';

/// Regression coverage for `DiscoveryProfileModel.fromJson`'s `gender`
/// mapping — the field that reaches every profile card (avatar placeholder,
/// gender-aware copy) across Discover, Search, Nearby, Interests, Shortlist,
/// Profile Views and Blocked Users, all of which parse the backend's shared
/// Discover card shape through this one model.
void main() {
  Map<String, dynamic> baseJson({Object? gender = 'Male'}) => {
        'id': 'p1',
        'matrimonyId': 'P1',
        'name': 'Member One',
        'age': 28,
        'location': 'Chennai, Tamil Nadu',
        'profession': 'Engineer',
        'education': 'B.E.',
        'photoUrls': <String>[],
        if (gender != null) 'gender': gender,
      };

  group('DiscoveryProfileModel.fromJson — gender', () {
    test('a populated gender reaches the entity', () {
      final profile = DiscoveryProfileModel.fromJson(baseJson(gender: 'Male'));

      expect(profile.gender, 'Male');
    });

    test('a different populated gender reaches the entity', () {
      final profile =
          DiscoveryProfileModel.fromJson(baseJson(gender: 'Female'));

      expect(profile.gender, 'Female');
    });

    test('a missing gender field falls back to an empty string, not a crash', () {
      final profile = DiscoveryProfileModel.fromJson(baseJson(gender: null));

      expect(profile.gender, '');
    });

    test('a null gender value falls back to an empty string', () {
      final json = baseJson()..['gender'] = null;

      final profile = DiscoveryProfileModel.fromJson(json);

      expect(profile.gender, '');
    });
  });
}
