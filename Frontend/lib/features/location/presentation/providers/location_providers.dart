import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/location_repository.dart';
import '../../domain/models/location_models.dart';

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(ref.watch(apiClientProvider));
});

/// The country list. Reference data, so it is kept alive for the session
/// rather than re-fetched every time the location step is rebuilt.
final countriesProvider = FutureProvider<List<LocationOption>>((ref) {
  ref.keepAlive();
  return ref.watch(locationRepositoryProvider).countries();
});

/// States/provinces for a country, keyed by its ISO code.
///
/// `.family` rather than a single provider holding a map: each country's list
/// then loads, errors and retries independently, and Riverpod caches them
/// separately, so switching back to a country already viewed is instant.
final statesProvider =
    FutureProvider.family<List<LocationOption>, String>((ref, countryCode) {
  if (countryCode.isEmpty) return Future.value(const <LocationOption>[]);
  ref.keepAlive();
  return ref.watch(locationRepositoryProvider).states(countryCode);
});

/// Cities for a state/province, keyed by its ISO 3166-2 code.
///
/// The whole subdivision is fetched once; filtering as the member types is
/// done locally by [filteredCitiesProvider], so typing costs no network.
final citiesProvider =
    FutureProvider.family<List<LocationOption>, String>((ref, stateCode) {
  if (stateCode.isEmpty) return Future.value(const <LocationOption>[]);
  ref.keepAlive();
  return ref.watch(locationRepositoryProvider).cities(stateCode);
});

/// A ([stateCode], query) pair, so city search can be a `.family` provider.
class CitySearch {
  const CitySearch(this.stateCode, this.query);

  final String stateCode;
  final String query;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CitySearch && other.stateCode == stateCode && other.query == query);

  @override
  int get hashCode => Object.hash(stateCode, query);
}

/// Cities matching a search string, ranked the same way the server ranks
/// them: prefix matches first, then substring matches, each already in
/// largest-first order from the API.
///
/// Filtering locally rather than calling the API per keystroke keeps typing
/// responsive and works offline once the subdivision is cached.
final filteredCitiesProvider =
    Provider.family<AsyncValue<List<LocationOption>>, CitySearch>((ref, search) {
  final cities = ref.watch(citiesProvider(search.stateCode));
  return cities.whenData((all) {
    final query = search.query.trim().toLowerCase();
    if (query.isEmpty) return all;

    final starts = <LocationOption>[];
    final contains = <LocationOption>[];
    for (final city in all) {
      final label = city.label.toLowerCase();
      if (label.startsWith(query)) {
        starts.add(city);
      } else if (label.contains(query)) {
        contains.add(city);
      }
    }
    return [...starts, ...contains];
  });
});
