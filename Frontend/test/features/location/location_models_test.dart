import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/location/domain/models/location_models.dart';

void main() {
  const india = LocationOption(code: 'IN', label: 'India');
  const singapore = LocationOption(code: 'SG', label: 'Singapore');
  const tamilNadu =
      LocationOption(code: 'IN-TN', label: 'Tamil Nadu', parentCode: 'IN', type: 'State');
  const kerala =
      LocationOption(code: 'IN-KL', label: 'Kerala', parentCode: 'IN', type: 'State');
  const chennai =
      LocationOption(code: 'IN-TN-CHENNAI', label: 'Chennai', parentCode: 'IN-TN');

  group('LocationOption', () {
    test('survives a cache round trip unchanged', () {
      final restored = LocationOption.fromCacheJson(tamilNadu.toJson());
      expect(restored.code, tamilNadu.code);
      expect(restored.label, tamilNadu.label);
      expect(restored.parentCode, 'IN');
      expect(restored.type, 'State');
    });

    test('reads the parent from whichever key the API used', () {
      // States carry countryCode, cities carry stateCode. One model, and the
      // parent is whichever is present.
      final state = LocationOption.fromJson(
        {'code': 'IN-TN', 'label': 'Tamil Nadu', 'type': 'State', 'countryCode': 'IN'},
      );
      final city = LocationOption.fromJson(
        {'code': 'IN-TN-CHENNAI', 'label': 'Chennai', 'stateCode': 'IN-TN', 'countryCode': 'IN'},
      );
      expect(state.parentCode, 'IN');
      expect(city.parentCode, 'IN-TN');
    });

    test('compares by code, not label', () {
      // The label is display text that may be corrected or translated; the
      // code is the identity.
      expect(
        const LocationOption(code: 'IN-TN', label: 'Tamil Nadu'),
        const LocationOption(code: 'IN-TN', label: 'தமிழ்நாடு'),
      );
    });
  });

  group('SelectedLocation cascade', () {
    const full = SelectedLocation(country: india, state: tamilNadu, city: chennai);

    test('changing country clears the state and city beneath it', () {
      // Keeping Tamil Nadu under Singapore would be a combination the server
      // rejects, so the cascade must not be able to produce it.
      final next = full.withCountry(singapore);
      expect(next.country, singapore);
      expect(next.state, isNull);
      expect(next.city, isNull);
    });

    test('re-picking the same country costs nothing', () {
      expect(full.withCountry(india), same(full));
    });

    test('changing state clears the city but keeps the country', () {
      final next = full.withState(kerala);
      expect(next.country, india);
      expect(next.state, kerala);
      expect(next.city, isNull);
    });

    test('re-picking the same state costs nothing', () {
      expect(full.withState(tamilNadu), same(full));
    });

    test('changing city leaves its parents alone', () {
      const madurai =
          LocationOption(code: 'IN-TN-MADURAI', label: 'Madurai', parentCode: 'IN-TN');
      final next = full.withCity(madurai);
      expect(next.country, india);
      expect(next.state, tamilNadu);
      expect(next.city, madurai);
    });

    test('is complete only when all three are chosen', () {
      expect(full.isComplete, isTrue);
      expect(const SelectedLocation(country: india, state: tamilNadu).isComplete, isFalse);
      expect(const SelectedLocation(country: india).isComplete, isFalse);
      expect(const SelectedLocation().isComplete, isFalse);
    });
  });
}
