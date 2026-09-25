import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/search/domain/entities/search_filters_entity.dart';

DiscoveryProfileEntity _profileWithHeight(String height) => DiscoveryProfileEntity(
      id: 'p1',
      matrimonyId: 'P1',
      name: 'Member',
      age: 28,
      location: 'Chennai, Tamil Nadu',
      profession: 'Engineer',
      education: 'B.E.',
      photoUrls: const ['https://example.test/photo.jpg'],
      height: height,
    );

void main() {
  group('SearchFilters.copyWith cascading', () {
    test('changing religion clears caste and community', () {
      const filters = SearchFilters(
        religion: 'Hindu',
        caste: 'Iyer',
        community: 'Vellalar',
      );

      final updated = filters.copyWith(religion: 'Christian');

      expect(updated.religion, 'Christian');
      expect(updated.caste, isNull);
      expect(updated.community, isNull);
    });

    test('setting religion to the same value preserves caste and community', () {
      const filters = SearchFilters(
        religion: 'Hindu',
        caste: 'Iyer',
        community: 'Vellalar',
      );

      final updated = filters.copyWith(religion: 'Hindu');

      expect(updated.caste, 'Iyer');
      expect(updated.community, 'Vellalar');
    });

    test('changing country clears state and city', () {
      const filters = SearchFilters(
        country: 'India (+91)',
        state: 'Tamil Nadu',
        city: 'Chennai',
      );

      final updated = filters.copyWith(country: 'United States (+1)');

      expect(updated.country, 'United States (+1)');
      expect(updated.state, isNull);
      expect(updated.city, isNull);
    });

    test('changing state clears city but preserves country', () {
      const filters = SearchFilters(
        country: 'India (+91)',
        state: 'Tamil Nadu',
        city: 'Chennai',
      );

      final updated = filters.copyWith(state: 'Kerala');

      expect(updated.country, 'India (+91)');
      expect(updated.state, 'Kerala');
      expect(updated.city, isNull);
    });

    test('setting country to the same value preserves state and city', () {
      const filters = SearchFilters(
        country: 'India (+91)',
        state: 'Tamil Nadu',
        city: 'Chennai',
      );

      final updated = filters.copyWith(country: 'India (+91)');

      expect(updated.state, 'Tamil Nadu');
      expect(updated.city, 'Chennai');
    });

    test('changing religion does not clear unrelated filters', () {
      const filters = SearchFilters(
        religion: 'Hindu',
        caste: 'Iyer',
        gender: 'Male',
        education: 'B.E / B.Tech / M.Tech',
        country: 'India (+91)',
        state: 'Tamil Nadu',
        city: 'Chennai',
      );

      final updated = filters.copyWith(religion: 'Christian');

      expect(updated.gender, 'Male');
      expect(updated.education, 'B.E / B.Tech / M.Tech');
      expect(updated.country, 'India (+91)');
      expect(updated.state, 'Tamil Nadu');
      expect(updated.city, 'Chennai');
    });

    test('changing country does not clear unrelated filters', () {
      const filters = SearchFilters(
        country: 'India (+91)',
        state: 'Tamil Nadu',
        city: 'Chennai',
        religion: 'Hindu',
        caste: 'Iyer',
        community: 'Vellalar',
      );

      final updated = filters.copyWith(country: 'United States (+1)');

      expect(updated.religion, 'Hindu');
      expect(updated.caste, 'Iyer');
      expect(updated.community, 'Vellalar');
    });

    test('explicitly setting caste alongside religion change keeps the new caste', () {
      const filters = SearchFilters(religion: 'Hindu', caste: 'Iyer');

      final updated = filters.copyWith(religion: 'Christian', caste: 'Other');

      expect(updated.religion, 'Christian');
      expect(updated.caste, 'Other');
    });

    test('clearing religion via clearReligion also clears caste and community', () {
      const filters = SearchFilters(
        religion: 'Hindu',
        caste: 'Iyer',
        community: 'Vellalar',
      );

      final updated = filters.copyWith(clearReligion: true);

      expect(updated.religion, isNull);
      expect(updated.caste, isNull);
      expect(updated.community, isNull);
    });
  });

  group('SearchFilters.matches — height', () {
    test('a profile exactly at the open-ended "6 ft 2 in+" floor matches', () {
      const filters = SearchFilters(heightMin: '6 ft 2 in+');
      final profile = _profileWithHeight('6 ft 2 in (188 cm)');

      expect(filters.matches(profile), isTrue);
    });

    test('a profile above the "6 ft 2 in+" floor matches', () {
      const filters = SearchFilters(heightMin: '6 ft 2 in+');
      final profile = _profileWithHeight('6 ft 5 in (196 cm)');

      expect(filters.matches(profile), isTrue);
    });

    test('a profile below the "6 ft 2 in+" floor is excluded', () {
      const filters = SearchFilters(heightMin: '6 ft 2 in+');
      final profile = _profileWithHeight('6 ft 0 in (183 cm)');

      expect(filters.matches(profile), isFalse);
    });

    test('"6 ft 2 in+" as heightMax excludes a taller profile', () {
      const filters = SearchFilters(heightMax: '6 ft 2 in+');
      final profile = _profileWithHeight('6 ft 5 in (196 cm)');

      expect(filters.matches(profile), isFalse);
    });

    test('normal bracketed range options still match correctly', () {
      const filters = SearchFilters(
        heightMin: '5 ft 4 in (162 cm)',
        heightMax: '5 ft 10 in (177 cm)',
      );

      expect(filters.matches(_profileWithHeight('5 ft 6 in (167 cm)')), isTrue);
      expect(filters.matches(_profileWithHeight('5 ft 0 in (152 cm)')), isFalse);
      expect(filters.matches(_profileWithHeight('6 ft 0 in (183 cm)')), isFalse);
    });

    test('a profile with missing height is not excluded by a height filter', () {
      const filters = SearchFilters(heightMin: '6 ft 2 in+');
      final profile = _profileWithHeight('');

      expect(filters.matches(profile), isTrue);
    });

    test('a profile with an unparseable height is not excluded by a height filter', () {
      const filters = SearchFilters(heightMin: '5 ft 4 in (162 cm)');
      final profile = _profileWithHeight('Prefer not to say');

      expect(filters.matches(profile), isTrue);
    });
  });

  // Regression: the toggle used to test isPsychologyCompleted, which the
  // backend sends as false for everyone (privacy) — so it hid every member.
  group('SearchFilters.matches — Completed Profile', () {
    DiscoveryProfileEntity profile({
      required bool profileComplete,
      bool isPsychologyCompleted = false,
    }) => DiscoveryProfileEntity(
      id: 'p1',
      matrimonyId: 'P1',
      name: 'Member',
      age: 28,
      location: 'Chennai, Tamil Nadu',
      profession: 'Engineer',
      education: 'B.E.',
      photoUrls: const ['https://example.test/photo.jpg'],
      profileComplete: profileComplete,
      isPsychologyCompleted: isPsychologyCompleted,
    );

    const on = SearchFilters(completedProfile: true);
    const off = SearchFilters();

    test('a complete profile passes regardless of Psychology fields', () {
      for (final psychology in [false, true]) {
        expect(
          on.matches(
            profile(profileComplete: true, isPsychologyCompleted: psychology),
          ),
          isTrue,
          reason: 'isPsychologyCompleted: $psychology',
        );
      }
    });

    test('an incomplete profile is excluded when the toggle is on — even with '
        'isPsychologyCompleted true', () {
      expect(on.matches(profile(profileComplete: false)), isFalse);
      expect(
        on.matches(
          profile(profileComplete: false, isPsychologyCompleted: true),
        ),
        isFalse,
      );
    });

    test('a member who never took Psychology (the backend default) is not '
        'hidden when complete', () {
      // DiscoveryProfileEntity's default for isPsychologyCompleted is false,
      // matching what the backend sends for every member.
      expect(on.matches(profile(profileComplete: true)), isTrue);
    });

    test('with the toggle off, nothing is filtered on completeness', () {
      expect(off.isEmpty, isTrue);
      for (final complete in [false, true]) {
        for (final psychology in [false, true]) {
          expect(
            off.matches(
              profile(
                profileComplete: complete,
                isPsychologyCompleted: psychology,
              ),
            ),
            isTrue,
          );
        }
      }
    });

    test('the toggle counts as an active filter', () {
      expect(on.isEmpty, isFalse);
      expect(on.activeCount, 1);
    });
  });
}
