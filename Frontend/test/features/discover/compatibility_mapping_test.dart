import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/data/models/discovery_profile_model.dart';

/// Regression coverage for the `compatibility` block of
/// `DiscoveryProfileModel.fromJson` — the ONLY place in the app where a
/// `CompatibilityEntity` is built from real data.
///
/// These scores are computed server-side by `CompatibilityService`
/// (`seekerFit` → `aiMatchPercent`, `overall` → `overallCompatibility`) and
/// the client is a pure transport: it must never re-derive, blend or
/// substitute a score. `astroMatchPercent` and `psychologyMatchPercent` are
/// deliberate server-side zeros today (no astrology/psychology engine
/// exists), which is why the cases below assert that a zero stays a zero and
/// a non-zero passes through untouched — the day those engines ship, the
/// values reach the UI with no client change.
///
/// The `?? 0` fallbacks in the mapper are null-guards for an absent field,
/// not placeholders; the missing/null cases pin that down.
void main() {
  /// The card shape every compatibility-bearing screen parses. [compatibility]
  /// is inserted verbatim when non-null so a test can omit it entirely.
  Map<String, dynamic> baseJson({Object? compatibility = const {}}) => {
        'id': 'p1',
        'matrimonyId': 'P1',
        'name': 'Member One',
        'age': 28,
        'location': 'Chennai, Tamil Nadu',
        'profession': 'Engineer',
        'education': 'B.E.',
        'photoUrls': <String>[],
        if (compatibility != null) 'compatibility': compatibility,
      };

  group('DiscoveryProfileModel.fromJson — compatibility', () {
    test('backend scores reach the entity verbatim', () {
      final profile = DiscoveryProfileModel.fromJson(
        baseJson(
          compatibility: {
            'aiMatchPercent': 87,
            'astroMatchPercent': 72,
            'psychologyMatchPercent': 64,
            'overallCompatibility': 79,
          },
        ),
      );

      // Verbatim: no rounding, no re-blending, no client-side recomputation.
      expect(profile.compatibility.aiMatchPercent, 87);
      expect(profile.compatibility.astroMatchPercent, 72);
      expect(profile.compatibility.psychologyMatchPercent, 64);
      expect(profile.compatibility.overallCompatibility, 79);
    });

    test('overallCompatibility is not re-derived from the other axes', () {
      // A backend `overall` that deliberately disagrees with any average of
      // the parts (it blends both directions 60/40 server-side). If the client
      // ever recomputed it, this would come back as something other than 40.
      final profile = DiscoveryProfileModel.fromJson(
        baseJson(
          compatibility: {
            'aiMatchPercent': 90,
            'astroMatchPercent': 90,
            'psychologyMatchPercent': 90,
            'overallCompatibility': 40,
          },
        ),
      );

      expect(
        profile.compatibility.overallCompatibility,
        40,
        reason: 'the client must transport the server score, not compute one',
      );
    });

    test('server-side zero placeholders stay zero, not invented values', () {
      // Exactly what `profile-feed.mapper.ts` sends today: astro/psychology
      // hardcoded to 0 because those engines do not exist yet.
      final profile = DiscoveryProfileModel.fromJson(
        baseJson(
          compatibility: {
            'aiMatchPercent': 55,
            'astroMatchPercent': 0,
            'psychologyMatchPercent': 0,
            'overallCompatibility': 55,
          },
        ),
      );

      expect(profile.compatibility.astroMatchPercent, 0);
      expect(profile.compatibility.psychologyMatchPercent, 0);
      expect(profile.compatibility.aiMatchPercent, 55);
    });

    test('an omitted compatibility block falls back to all-zero, not a crash',
        () {
      final profile = DiscoveryProfileModel.fromJson(baseJson(compatibility: null));

      expect(profile.compatibility.aiMatchPercent, 0);
      expect(profile.compatibility.astroMatchPercent, 0);
      expect(profile.compatibility.psychologyMatchPercent, 0);
      expect(profile.compatibility.overallCompatibility, 0);
    });

    test('a null compatibility value falls back to all-zero, not a crash', () {
      final json = baseJson()..['compatibility'] = null;

      final profile = DiscoveryProfileModel.fromJson(json);

      expect(profile.compatibility.overallCompatibility, 0);
    });

    test('a partial compatibility block keeps the fields it does carry', () {
      final profile = DiscoveryProfileModel.fromJson(
        baseJson(compatibility: {'aiMatchPercent': 61}),
      );

      expect(profile.compatibility.aiMatchPercent, 61);
      expect(profile.compatibility.overallCompatibility, 0);
    });

    test('the five hub-report axes are never populated from the feed', () {
      // lifestyle/family/education/values/goals have no field in the feed
      // contract. They must stay at their zero defaults rather than being
      // synthesized on the client — CompatibilityCardSection gates each one
      // at >= 80, so a fabricated value would render a claim about a member
      // that no backend ever made.
      final profile = DiscoveryProfileModel.fromJson(
        baseJson(
          compatibility: {
            'aiMatchPercent': 95,
            'overallCompatibility': 95,
          },
        ),
      );

      expect(profile.compatibility.lifestyleMatchPercent, 0);
      expect(profile.compatibility.familyMatchPercent, 0);
      expect(profile.compatibility.educationMatchPercent, 0);
      expect(profile.compatibility.valuesMatchPercent, 0);
      expect(profile.compatibility.goalsMatchPercent, 0);
    });

    test('compatibility survives a fromJson/toJson round trip', () {
      final original = baseJson(
        compatibility: {
          'aiMatchPercent': 87,
          'astroMatchPercent': 72,
          'psychologyMatchPercent': 64,
          'overallCompatibility': 79,
        },
      );

      final json = DiscoveryProfileModel.fromJson(original).toJson();
      final block = json['compatibility'] as Map<String, dynamic>;

      expect(block['aiMatchPercent'], 87);
      expect(block['astroMatchPercent'], 72);
      expect(block['psychologyMatchPercent'], 64);
      expect(block['overallCompatibility'], 79);
    });
  });
}
