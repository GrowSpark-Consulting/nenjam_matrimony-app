import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/data/models/discovery_profile_model.dart';

/// Regression coverage for `DiscoveryProfileModel.fromJson`'s badge-flag
/// mapping — `isVerified`, `isPremium`, `phoneVerified`, `photoProtected`,
/// `horoscopeAvailable`, `isPsychologyCompleted`, `isOnline` and
/// `profileComplete`.
///
/// These flags are pure pass-throughs: the backend's `ProfileFeedMapper`
/// decides each one and the client must never re-derive or override it. Some
/// of them are server-side placeholders today (`isPremium`, `isOnline`,
/// `horoscopeAvailable` and `isPsychologyCompleted` are hardcoded `false` in
/// `profile-feed.mapper.ts` because no subscription / presence / astrology /
/// psychology engine is wired yet), which is exactly why this file asserts on
/// `true` as well: it pins the client as already correct, so the day the
/// backend starts sending real values they reach the card with no client
/// change at all. A failure here means someone hardcoded a badge on the
/// client instead of trusting the response.
///
/// The `?? false` in the mapper is a null-guard for a field the response
/// omits — not a placeholder — and the missing/null cases below lock that in.
void main() {
  /// The card shape every badge-bearing screen parses, with only the required
  /// fields set; badge flags are supplied per test via [extra].
  Map<String, dynamic> baseJson([Map<String, dynamic> extra = const {}]) => {
        'id': 'p1',
        'matrimonyId': 'P1',
        'name': 'Member One',
        'age': 28,
        'location': 'Chennai, Tamil Nadu',
        'profession': 'Engineer',
        'education': 'B.E.',
        'photoUrls': <String>[],
        ...extra,
      };

  const badgeFields = [
    'isVerified',
    'isPremium',
    'isPsychologyCompleted',
    'isOnline',
    'horoscopeAvailable',
    'photoProtected',
    'phoneVerified',
    'profileComplete',
  ];

  /// Reads a badge off the entity by its JSON key, so each case below can be
  /// driven over [badgeFields] rather than repeated eight times.
  bool badgeOf(DiscoveryProfileModel profile, String field) => switch (field) {
        'isVerified' => profile.isVerified,
        'isPremium' => profile.isPremium,
        'isPsychologyCompleted' => profile.isPsychologyCompleted,
        'isOnline' => profile.isOnline,
        'horoscopeAvailable' => profile.horoscopeAvailable,
        'photoProtected' => profile.photoProtected,
        'phoneVerified' => profile.phoneVerified,
        'profileComplete' => profile.profileComplete,
        _ => throw ArgumentError('unknown badge field: $field'),
      };

  group('DiscoveryProfileModel.fromJson — badge flags', () {
    for (final field in badgeFields) {
      test('$field: true in the response reaches the entity as true', () {
        final profile =
            DiscoveryProfileModel.fromJson(baseJson({field: true}));

        expect(
          badgeOf(profile, field),
          isTrue,
          reason: '$field must pass through from the response, not be '
              'hardcoded on the client',
        );
      });

      test('$field: false in the response reaches the entity as false', () {
        final profile =
            DiscoveryProfileModel.fromJson(baseJson({field: false}));

        expect(badgeOf(profile, field), isFalse);
      });

      test('$field: an omitted field falls back to false, not a crash', () {
        final profile = DiscoveryProfileModel.fromJson(baseJson());

        expect(badgeOf(profile, field), isFalse);
      });

      test('$field: an explicit null falls back to false, not a crash', () {
        final profile =
            DiscoveryProfileModel.fromJson(baseJson({field: null}));

        expect(badgeOf(profile, field), isFalse);
      });
    }

    test('every badge set to true survives a fromJson/toJson round trip', () {
      final allTrue = baseJson({for (final f in badgeFields) f: true});

      final json = DiscoveryProfileModel.fromJson(allTrue).toJson();

      for (final field in badgeFields) {
        expect(json[field], isTrue, reason: '$field lost on serialization');
      }
    });

    test('badges are independent — one true flag does not set the others', () {
      final profile =
          DiscoveryProfileModel.fromJson(baseJson({'isVerified': true}));

      expect(profile.isVerified, isTrue);
      for (final field in badgeFields.where((f) => f != 'isVerified')) {
        expect(badgeOf(profile, field), isFalse, reason: '$field leaked true');
      }
    });
  });
}
