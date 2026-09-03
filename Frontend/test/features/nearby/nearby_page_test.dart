import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nenjam_matrimony/core/services/location/device_location_service.dart';
import 'package:nenjam_matrimony/core/services/location/location_providers.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/nearby/domain/repositories/nearby_repository.dart';
import 'package:nenjam_matrimony/features/nearby/presentation/pages/nearby_page.dart';
import 'package:nenjam_matrimony/features/nearby/presentation/providers/nearby_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Near Me's five screen states.
///
/// The permission outcomes are the point of this suite: an OS permission
/// dialog cannot be granted or denied from a widget test, so without the
/// injectable [DeviceLocationService] seam none of the denied / blocked /
/// services-off paths could be exercised at all — and those are exactly the
/// paths a user hits first.
void main() {
  group('NearbyPage', () {
    testWidgets('shows profiles sorted with their distance when granted', (
      tester,
    ) async {
      await _pump(
        tester,
        location: _FakeLocationService(const LocationSuccess(
          latitude: 13.0827,
          longitude: 80.2707,
          accuracyMetres: 20,
        )),
        repository: _FakeNearbyRepository([
          _profile(id: '1', name: 'Asha', distanceKm: 2.3),
          _profile(id: '2', name: 'Divya', distanceKm: 8.7),
          _profile(id: '3', name: 'Kavya', distanceKm: 45),
        ]),
      );

      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('2.3 km away'), findsOneWidget);
      expect(find.text('8.7 km away'), findsOneWidget);
      // Whole numbers drop the redundant ".0".
      expect(find.text('45 km away'), findsOneWidget);
    });

    testWidgets('describes a sub-kilometre distance without rounding to 0', (
      tester,
    ) async {
      await _pump(
        tester,
        location: _FakeLocationService(const LocationSuccess(
          latitude: 13.0827,
          longitude: 80.2707,
          accuracyMetres: 20,
        )),
        repository: _FakeNearbyRepository([
          _profile(id: '1', name: 'Asha', distanceKm: 0.4),
        ]),
      );

      expect(find.text('Less than 1 km away'), findsOneWidget);
      expect(find.text('0 km away'), findsNothing);
    });

    testWidgets('stores the caller own location once a fix is granted', (
      tester,
    ) async {
      final repository = _FakeNearbyRepository(const []);

      await _pump(
        tester,
        location: _FakeLocationService(const LocationSuccess(
          latitude: 13.0827,
          longitude: 80.2707,
          accuracyMetres: 20,
        )),
        repository: repository,
      );

      // Being findable by others is half the feature; a granted fix that was
      // never stored would leave the user invisible in everyone else's results.
      expect(repository.storedLatitude, 13.0827);
      expect(repository.storedLongitude, 80.2707);
      expect(repository.storedAccuracyMetres, 20);
    });

    testWidgets('still shows results when the location is only approximate', (
      tester,
    ) async {
      await _pump(
        tester,
        // 1500m accuracy is what an Android "Approximate" grant reports.
        location: _FakeLocationService(const LocationSuccess(
          latitude: 13.0827,
          longitude: 80.2707,
          accuracyMetres: 1500,
        )),
        repository: _FakeNearbyRepository([
          _profile(id: '1', name: 'Asha', distanceKm: 3.2),
        ]),
      );

      expect(find.text('Asha'), findsOneWidget);
      expect(
        find.text(
          'You shared an approximate location, so distances are rough.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('offers Enable Location when permission was denied', (
      tester,
    ) async {
      await _pump(
        tester,
        location: _FakeLocationService(const LocationPermissionDenied()),
        repository: _FakeNearbyRepository(const []),
      );

      expect(
        find.text('Location access is required to discover people near you.'),
        findsOneWidget,
      );
      expect(find.text('Enable Location'), findsOneWidget);
    });

    testWidgets('does not crash and loads after the user allows on retry', (
      tester,
    ) async {
      final location = _FakeLocationService(const LocationPermissionDenied());

      await _pump(
        tester,
        location: location,
        repository: _FakeNearbyRepository([
          _profile(id: '1', name: 'Asha', distanceKm: 1.1),
        ]),
      );

      expect(find.text('Enable Location'), findsOneWidget);

      // The user taps Enable Location and allows at the OS prompt.
      location.result = const LocationSuccess(
        latitude: 13.0827,
        longitude: 80.2707,
        accuracyMetres: 20,
      );
      await tester.tap(find.text('Enable Location'));
      await tester.pumpAndSettle();

      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('1.1 km away'), findsOneWidget);
    });

    testWidgets('offers Settings instead of a retry when permanently denied', (
      tester,
    ) async {
      await _pump(
        tester,
        location: _FakeLocationService(
          const LocationPermissionPermanentlyDenied(),
        ),
        repository: _FakeNearbyRepository(const []),
      );

      // Retrying cannot help once the OS has stopped showing its dialog, so
      // the button must not claim otherwise.
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Enable Location'), findsNothing);
    });

    testWidgets('distinguishes location services being switched off', (
      tester,
    ) async {
      await _pump(
        tester,
        location: _FakeLocationService(const LocationServiceDisabled()),
        repository: _FakeNearbyRepository(const []),
      );

      expect(find.text('Location is turned off'), findsOneWidget);
      expect(find.text('Turn On Location'), findsOneWidget);
    });

    testWidgets('shows the location error state when no fix is available', (
      tester,
    ) async {
      await _pump(
        tester,
        location: _FakeLocationService(const LocationUnavailable('timeout')),
        repository: _FakeNearbyRepository(const []),
      );

      expect(
        find.text('Unable to get your location. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('shows the empty state naming the real radius', (tester) async {
      await _pump(
        tester,
        location: _FakeLocationService(const LocationSuccess(
          latitude: 13.0827,
          longitude: 80.2707,
          accuracyMetres: 20,
        )),
        repository: _FakeNearbyRepository(const []),
      );

      expect(
        find.text('No profiles found within 100 km of your location.'),
        findsOneWidget,
      );
    });

    testWidgets('separates a failed request from a failed location', (
      tester,
    ) async {
      await _pump(
        tester,
        location: _FakeLocationService(const LocationSuccess(
          latitude: 13.0827,
          longitude: 80.2707,
          accuracyMetres: 20,
        )),
        repository: _FakeNearbyRepository(const [], throwOnFetch: true),
      );

      // Telling someone their location is broken when the API call failed
      // sends them to the wrong settings screen.
      expect(
        find.text('Unable to load profiles near you. Please try again.'),
        findsOneWidget,
      );
      expect(
        find.text('Unable to get your location. Please try again.'),
        findsNothing,
      );
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required DeviceLocationService location,
  required NearbyRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceLocationServiceProvider.overrideWithValue(location),
        nearbyRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NearbyPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DiscoveryProfileEntity _profile({
  required String id,
  required String name,
  required double distanceKm,
}) => DiscoveryProfileEntity(
  id: id,
  matrimonyId: id,
  name: name,
  age: 27,
  location: 'Chennai',
  profession: 'Engineer',
  education: 'B.E.',
  photoUrls: const [],
  distanceKm: distanceKm,
  gender: 'Female',
);

/// Returns whatever [result] currently holds, so a test can flip a denial into
/// a grant between the first load and a retry.
class _FakeLocationService implements DeviceLocationService {
  _FakeLocationService(this.result);

  LocationResult result;

  @override
  Future<LocationResult?> checkPermissionOnly() async =>
      result is LocationSuccess ? null : result;

  @override
  Future<LocationResult> requestAndFetch() async => result;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _FakeNearbyRepository implements NearbyRepository {
  _FakeNearbyRepository(this.profiles, {this.throwOnFetch = false});

  final List<DiscoveryProfileEntity> profiles;
  final bool throwOnFetch;

  double? storedLatitude;
  double? storedLongitude;
  int? storedAccuracyMetres;

  @override
  Future<List<DiscoveryProfileEntity>> getNearbyProfiles({
    required double latitude,
    required double longitude,
    double radiusKm = 100,
    int page = 1,
    int limit = 50,
  }) async {
    if (throwOnFetch) throw Exception('network down');
    return profiles;
  }

  @override
  Future<void> updateMyLocation({
    required double latitude,
    required double longitude,
    int? accuracyMetres,
  }) async {
    storedLatitude = latitude;
    storedLongitude = longitude;
    storedAccuracyMetres = accuracyMetres;
  }
}
