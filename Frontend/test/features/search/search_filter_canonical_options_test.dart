import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/constants/profile_options.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/search/domain/entities/search_filters_entity.dart';

/// Local fixture, mirroring `search_providers_test.dart`'s `_profile`.
DiscoveryProfileEntity discoveryProfile(
  String id, {
  String religion = 'Hindu',
  String caste = '',
  String diet = '',
  String height = '',
  String location = 'Chennai, Tamil Nadu',
  String annualIncome = '',
}) => DiscoveryProfileEntity(
  id: id,
  matrimonyId: id.toUpperCase(),
  name: 'Member $id',
  age: 28,
  location: location,
  profession: 'Engineer',
  education: 'B.E.',
  photoUrls: const ['https://example.test/photo.jpg'],
  religion: religion,
  caste: caste,
  diet: diet,
  height: height,
  annualIncome: annualIncome,
);

/// Search filter options that are compared against a profile's stored value
/// must come from [ProfileOptions] — the same lists the registration wizard
/// writes from. When the two drift, the filter silently matches nothing:
/// Search's diet list was missing 'Jain', so no Jain profile was reachable.
///
/// These tests pin the canonical source for the migrated lists, and pin the
/// retained Search-only lists as deliberately separate.
void main() {
  group('diet options are canonical', () {
    test('every wizard diet is offered by Search', () {
      // The sheet now passes ProfileOptions.diets straight through.
      expect(ProfileOptions.diets, contains('Jain'));
      expect(
        ProfileOptions.diets,
        containsAll(<String>[
          'Vegetarian',
          'Non-Vegetarian',
          'Eggetarian',
          'Vegan',
        ]),
      );
    });

    test('a Jain profile is now reachable by the diet filter', () {
      const filters = SearchFilters(diet: 'Jain');

      expect(filters.matches(discoveryProfile('a', diet: 'Jain')), isTrue);
      expect(
        filters.matches(discoveryProfile('b', diet: 'Vegetarian')),
        isFalse,
      );
    });
  });

  group('religion / community options are canonical', () {
    test('religions come from the wizard list', () {
      expect(
        ProfileOptions.religions,
        containsAll(<String>[
          'Hindu',
          'Christian',
          'Muslim',
          'Jain',
          'Sikh',
          'Buddhist',
          'Inter-Religion',
        ]),
      );
    });

    test('communities are scoped to the chosen religion', () {
      final hindu = ProfileOptions.communitiesFor('Hindu');

      expect(hindu, isNotEmpty);
      // An unchosen religion must widen to the full list, never empty out.
      expect(ProfileOptions.communitiesFor(''), isNotEmpty);
    });

    test('a religion+caste selection still matches', () {
      final caste = ProfileOptions.subCommunities.first;
      final filters = SearchFilters(religion: 'Hindu', caste: caste);

      expect(
        filters.matches(
          discoveryProfile('a', religion: 'Hindu', caste: caste),
        ),
        isTrue,
      );
      expect(
        filters.matches(
          discoveryProfile('b', religion: 'Christian', caste: caste),
        ),
        isFalse,
      );
    });
  });

  group('location options are canonical and cascade', () {
    test('countries carry no dialing-code suffix', () {
      // The old Search list read 'India (+91)' — a value no profile holds.
      expect(ProfileOptions.countries, contains('India'));
      expect(
        ProfileOptions.countries.any((c) => c.contains('(+')),
        isFalse,
        reason: 'dialing codes belong to phone entry, not a location filter',
      );
    });

    test('states are scoped to the chosen country, cities to the state', () {
      expect(ProfileOptions.statesFor('India'), contains('Tamil Nadu'));
      expect(ProfileOptions.statesFor(''), isNotEmpty);
      expect(ProfileOptions.citiesFor(''), isNotEmpty);
    });

    test('city filter still matches a profile location substring', () {
      const filters = SearchFilters(city: 'Chennai');

      expect(
        filters.matches(discoveryProfile('a', location: 'Chennai, TN')),
        isTrue,
      );
      expect(
        filters.matches(discoveryProfile('b', location: 'Madurai, TN')),
        isFalse,
      );
    });
  });

  group('cascading reset behaviour is preserved', () {
    test('changing religion clears caste and community', () {
      const before = SearchFilters(
        religion: 'Hindu',
        caste: 'Iyer',
        community: 'Iyer',
      );

      final after = before.copyWith(religion: 'Christian');

      expect(after.religion, 'Christian');
      expect(after.caste, isNull);
      expect(after.community, isNull);
    });

    test('changing country clears state and city', () {
      const before = SearchFilters(
        country: 'India',
        state: 'Tamil Nadu',
        city: 'Chennai',
      );

      final after = before.copyWith(country: 'Singapore');

      expect(after.state, isNull);
      expect(after.city, isNull);
    });

    test('changing state clears city but keeps country', () {
      const before = SearchFilters(
        country: 'India',
        state: 'Tamil Nadu',
        city: 'Chennai',
      );

      final after = before.copyWith(state: 'Karnataka');

      expect(after.country, 'India');
      expect(after.state, 'Karnataka');
      expect(after.city, isNull);
    });
  });

  group('Search-only lists stay separate by design', () {
    test('income brackets are parsed as floors, not matched as strings', () {
      // ' PA'-suffixed bracket vs. the profile's unsuffixed band.
      const filters = SearchFilters(annualIncome: '10 - 20 Lakhs PA');

      expect(
        filters.matches(discoveryProfile('a', annualIncome: '20 - 50 Lakhs')),
        isTrue,
      );
    });

    test('height brackets are parsed to cm, not matched as strings', () {
      const filters = SearchFilters(heightMin: '5 ft 6 in (167 cm)');

      expect(
        filters.matches(discoveryProfile('a', height: '5 ft 8 in (172 cm)')),
        isTrue,
      );
      expect(
        filters.matches(discoveryProfile('b', height: '5 ft 0 in (152 cm)')),
        isFalse,
      );
    });
  });
}
