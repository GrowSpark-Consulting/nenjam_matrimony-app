import 'package:flutter_test/flutter_test.dart';

import 'package:nenjam_matrimony/core/constants/profile_options.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/onboarding_scaffold.dart';

/// Re-opening the location step must not discard what a member already saved.
///
/// The state/city/country lists in [ProfileOptions] are a hand-curated subset,
/// and the live database holds answers outside it. Every value below is a real
/// one taken from the production `user_profiles` table, not an invented case:
///
///   states  — Punjab, Goa, Uttar Pradesh, TN   (none offered by the list)
///   cities  — Bengaluru, chennai, Patna, Vellore, Mangaluru, Tiruchirappalli
///
/// `restore` blanks anything the list does not contain, because the dropdown
/// asserts on a value absent from its items. For location that turned a
/// re-opened step into an empty required field, and the next save wrote the
/// replacement over a perfectly good stored answer.
///
/// These tests pin the fix and, just as importantly, pin what it must NOT do:
/// no trimming into a different value, no case folding, no alias resolution.
/// `Bengaluru` and `Bangalore` stay two different answers until an
/// authoritative dataset says otherwise.
void main() {
  group('optionsWith — keeps a stored answer displayable', () {
    test('appends a state the curated list does not offer', () {
      for (final stored in ['Punjab', 'Goa', 'Uttar Pradesh', 'TN']) {
        final options = OnboardingScaffold.optionsWith(
          ProfileOptions.states,
          stored,
        );

        expect(
          options,
          contains(stored),
          reason: '"$stored" is stored on a real profile and must survive',
        );
        // The dropdown asserts unless its value is among its items.
        expect(options.where((o) => o == stored).length, 1);
      }
    });

    test('appends a city the state list does not offer', () {
      for (final stored in [
        'Bengaluru',
        'chennai',
        'Patna',
        'Vellore',
        'Mangaluru',
        'Tiruchirappalli',
      ]) {
        final options = OnboardingScaffold.optionsWith(
          ProfileOptions.citiesFor('Karnataka'),
          stored,
        );
        expect(options, contains(stored));
      }
    });

    test('leaves the list untouched when the value is already offered', () {
      final options = OnboardingScaffold.optionsWith(
        ProfileOptions.states,
        'Tamil Nadu',
      );

      expect(options, same(ProfileOptions.states));
    });

    test('adds nothing for an unanswered field', () {
      final options = OnboardingScaffold.optionsWith(ProfileOptions.states, '');

      expect(options, same(ProfileOptions.states));
    });

    test('never rewrites the stored value', () {
      // The whole point: the answer is displayed as stored. Reconciling
      // Bengaluru with Bangalore, or chennai with Chennai, needs an
      // authoritative source — guessing it here is silent data loss.
      final options = OnboardingScaffold.optionsWith(
        ProfileOptions.citiesFor('Karnataka'),
        'Bengaluru',
      );

      expect(options, contains('Bengaluru'));
      expect(
        options.contains('Bangalore'),
        isTrue,
        reason: 'the canonical entry stays; the two are not merged',
      );
    });

    test('does not case-fold onto a similar entry', () {
      final options = OnboardingScaffold.optionsWith(
        ProfileOptions.citiesFor('Tamil Nadu'),
        'chennai',
      );

      expect(options, containsAll(['Chennai', 'chennai']));
    });
  });

  group('the location payload cannot erase what it does not carry', () {
    test('an unanswered field is omitted, not sent as empty', () {
      // Paired with the backend's mergeDraftSection, which spreads the stored
      // section before applying the patch: omitting a field is what makes a
      // partial save preserve area/pinCode/nativePlace instead of blanking
      // them. Sending "" would overwrite a real stored value with nothing.
      const partial = LocationDetails(state: 'Punjab', city: 'Amritsar');

      final json = partial.toJson();

      expect(json, containsPair('state', 'Punjab'));
      expect(json, containsPair('city', 'Amritsar'));
      expect(json.containsKey('area'), isFalse);
      expect(json.containsKey('pinCode'), isFalse);
      expect(json.containsKey('nativePlace'), isFalse);
    });

    test('carries every answered field through unchanged', () {
      const full = LocationDetails(
        country: 'India',
        state: 'Bihar',
        city: 'Patna',
        area: 'Kankarbagh',
        pinCode: '800020',
        nativePlace: 'Gaya',
      );

      expect(full.toJson(), {
        'country': 'India',
        'state': 'Bihar',
        'city': 'Patna',
        'area': 'Kankarbagh',
        'pinCode': '800020',
        'nativePlace': 'Gaya',
      });
    });

    test('round-trips a legacy value the option lists do not contain', () {
      // GET /profiles/draft → fromJson → toJson → PATCH. A value must survive
      // the round trip byte-for-byte; no trimming, no casing change.
      const stored = {'country': 'India', 'state': 'TN', 'city': 'chennai'};

      final restored = LocationDetails.fromJson(stored);

      expect(restored.state, 'TN');
      expect(restored.city, 'chennai');
      expect(restored.toJson(), containsPair('state', 'TN'));
      expect(restored.toJson(), containsPair('city', 'chennai'));
    });

    test('an absent country falls back without inventing a location', () {
      // 15 of 56 live profiles have a null country.
      final restored = LocationDetails.fromJson(const {'state': 'Goa'});

      expect(restored.country, 'India');
      expect(restored.state, 'Goa');
      expect(restored.city, isEmpty);
    });
  });

  group('restore — unchanged for closed vocabularies', () {
    test('still blanks a value outside a non-location list', () {
      // Religion, marital status and the rest are closed vocabularies where
      // blanking is correct. This fix deliberately did not touch them.
      expect(OnboardingScaffold.restore('Jedi', ProfileOptions.religions), '');
    });

    test('still returns a value the list offers', () {
      final religion = ProfileOptions.religions.first;
      expect(OnboardingScaffold.restore(religion, ProfileOptions.religions),
          religion);
    });
  });
}
