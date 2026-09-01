import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nenjam_matrimony/core/services/location/device_location_service.dart';
import 'package:nenjam_matrimony/core/services/location/location_providers.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/presentation/pages/discover_page.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/nearby/domain/repositories/nearby_repository.dart';
import 'package:nenjam_matrimony/features/nearby/presentation/providers/nearby_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Discover's "Near You" section, backed by the real Nearby feature.
///
/// Two properties carry most of the weight here:
///
///   * Opening Discover checks the permission STATUS but never prompts. The
///     section is on screen for every user, so a prompt triggered by the
///     section appearing would be a system dialog raised by nothing more than
///     launching the app.
///   * The section survives an empty main feed. Near Me filters on gender,
///     safety and distance — not partner preferences — so it can have people
///     to show precisely when the preference-filtered feed does not.
void main() {
  group('Discover Near You — permission on open', () {
    testWidgets('already granted: resolves and loads without prompting', (
      tester,
    ) async {
      final location = _FakeLocationService(_granted);
      final repository = _FakeNearbyRepository([
        _profile(id: '1', name: 'Asha', distanceKm: 2.3),
      ]);

      await _pumpDiscover(tester, location: location, repository: repository);

      // Status was checked, and it came back granted — so reading a position
      // raises no dialog (see _FakeLocationService.promptsShown).
      expect(location.statusChecks, 1);
      expect(location.promptsShown, 0);
      expect(repository.fetchCalls, 1);
      expect(repository.updateLocationCalls, 1);
      expect(find.text('Asha, 27'), findsOneWidget);
    });

    testWidgets('not granted: shows the inline CTA and never prompts', (
      tester,
    ) async {
      final location = _FakeLocationService(const LocationPermissionDenied());
      final repository = _FakeNearbyRepository(const []);

      await _pumpDiscover(tester, location: location, repository: repository);

      expect(location.statusChecks, 1);
      // The whole point: no OS dialog for merely opening Discover.
      expect(location.promptsShown, 0);
      // And nothing fetched for a user whose location we cannot read.
      expect(repository.fetchCalls, 0);

      expect(find.text('Find people near you'), findsOneWidget);
      expect(
        find.text(
          'Enable location to discover compatible profiles within 100 km of you.',
        ),
        findsOneWidget,
      );
      expect(find.text('Enable Location'), findsOneWidget);
    });

    testWidgets('permanently denied: offers Settings, not a dead retry', (
      tester,
    ) async {
      final location = _FakeLocationService(
        const LocationPermissionPermanentlyDenied(),
      );

      await _pumpDiscover(
        tester,
        location: location,
        repository: _FakeNearbyRepository(const []),
      );

      expect(location.promptsShown, 0);
      expect(find.text('Open Settings'), findsOneWidget);
      // Retrying cannot help once the OS has stopped asking.
      expect(find.text('Enable Location'), findsNothing);
    });

    testWidgets('location services off is its own state', (tester) async {
      await _pumpDiscover(
        tester,
        location: _FakeLocationService(const LocationServiceDisabled()),
        repository: _FakeNearbyRepository(const []),
      );

      expect(find.text('Location is turned off'), findsOneWidget);
      expect(find.text('Turn On Location'), findsOneWidget);
    });
  });

  group('Discover Near You — user-initiated permission', () {
    testWidgets('tapping Enable Location is what raises the OS dialog', (
      tester,
    ) async {
      final location = _FakeLocationService(const LocationPermissionDenied());
      final repository = _FakeNearbyRepository(const []);

      await _pumpDiscover(tester, location: location, repository: repository);
      expect(location.promptsShown, 0);

      await _tapEnableLocation(tester);

      expect(location.promptsShown, 1);
      expect(
        find.text('Enable Location'),
        findsOneWidget,
        reason: 'still denied, and the OS will ask again',
      );
    });

    testWidgets('allowing at the prompt loads profiles', (tester) async {
      final location = _FakeLocationService(const LocationPermissionDenied());
      final repository = _FakeNearbyRepository([
        _profile(id: '1', name: 'Asha', distanceKm: 2.3),
        _profile(id: '2', name: 'Divya', distanceKm: 8.7),
      ]);

      await _pumpDiscover(tester, location: location, repository: repository);

      // The user allows at the system dialog.
      location.result = _granted;
      await _tapEnableLocation(tester);

      expect(find.text('Asha, 27'), findsOneWidget);
      expect(find.text('Divya, 27'), findsOneWidget);
      // The existing Discover card already rendered distanceKm — the data
      // source changed, the card did not.
      expect(find.text('2.3 km away • B.E.'), findsOneWidget);
      expect(repository.updateLocationCalls, 1);
    });

    testWidgets('a failed request says so, and offers a retry', (tester) async {
      await _pumpDiscover(
        tester,
        location: _FakeLocationService(_granted),
        repository: _FakeNearbyRepository(const [], throwOnFetch: true),
      );

      expect(
        find.text('Unable to load profiles near you. Please try again.'),
        findsOneWidget,
      );
      // Not a location problem — saying so would send the user to a settings
      // screen that cannot help them.
      expect(
        find.text('Unable to get your location. Please try again.'),
        findsNothing,
      );
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('a failed fix reports a location error', (tester) async {
      await _pumpDiscover(
        tester,
        location: _FakeLocationService(const LocationUnavailable('timeout')),
        repository: _FakeNearbyRepository(const []),
      );

      expect(
        find.text('Unable to get your location. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('nobody within the radius hides the section entirely', (
      tester,
    ) async {
      await _pumpDiscover(
        tester,
        location: _FakeLocationService(_granted),
        repository: _FakeNearbyRepository(const []),
      );

      // An empty section in a browsing feed is noise; the dedicated Near Me
      // screen is where "nobody within 100 km" gets explained.
      expect(find.text('Near You'), findsNothing);
      expect(find.text('Find people near you'), findsNothing);
    });
  });

  group('Discover Near You — independent of the main feed', () {
    testWidgets('empty feed + no permission still shows both states', (
      tester,
    ) async {
      await _pumpDiscover(
        tester,
        location: _FakeLocationService(const LocationPermissionDenied()),
        repository: _FakeNearbyRepository(const []),
        feed: _emptyFeed(),
      );

      // The main feed says its piece...
      expect(find.text('No matching profiles found.'), findsOneWidget);
      // ...and Near You is still reachable underneath it.
      expect(find.text('Find people near you'), findsOneWidget);
      expect(find.text('Enable Location'), findsOneWidget);
    });

    testWidgets('empty feed + granted still shows nearby profiles', (
      tester,
    ) async {
      await _pumpDiscover(
        tester,
        location: _FakeLocationService(_granted),
        repository: _FakeNearbyRepository([
          _profile(id: '1', name: 'Asha', distanceKm: 2.3),
        ]),
        feed: _emptyFeed(),
      );

      // Nobody matches the saved preferences, but somebody is nearby — which
      // is exactly the case the old full-page empty state used to hide.
      expect(find.text('No matching profiles found.'), findsOneWidget);
      expect(find.text('Asha, 27'), findsOneWidget);
    });

    testWidgets('empty feed + empty nearby renders both without conflict', (
      tester,
    ) async {
      await _pumpDiscover(
        tester,
        location: _FakeLocationService(_granted),
        repository: _FakeNearbyRepository(const []),
        feed: _emptyFeed(),
      );

      expect(find.text('No matching profiles found.'), findsOneWidget);
      expect(find.text('Near You'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty feed does not make Near You fetch anything extra', (
      tester,
    ) async {
      final repository = _FakeNearbyRepository(const []);

      await _pumpDiscover(
        tester,
        location: _FakeLocationService(const LocationPermissionDenied()),
        repository: repository,
        feed: _emptyFeed(),
      );

      // Nearby must not depend on, or compensate for, the Discover feed.
      expect(repository.fetchCalls, 0);
    });
  });

  group('Discover Near You — caching', () {
    testWidgets('re-entering Discover does not refetch or re-read GPS', (
      tester,
    ) async {
      final location = _FakeLocationService(_granted);
      final repository = _FakeNearbyRepository([
        _profile(id: '1', name: 'Asha', distanceKm: 2.3),
      ]);

      // One container across both pumps, standing in for the app-wide scope a
      // real navigation away and back would keep alive.
      final container = ProviderContainer(
        overrides: _overrides(
          location: location,
          repository: repository,
          feed: _feed(),
        ),
      );
      addTearDown(container.dispose);

      await _pumpWithContainer(tester, container);
      expect(repository.fetchCalls, 1);
      expect(location.fixReads, 1);

      // Leave Discover and come back.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _pumpWithContainer(tester, container);

      expect(repository.fetchCalls, 1, reason: 'results should be reused');
      expect(location.fixReads, 1, reason: 'GPS should not be re-read');
      expect(
        location.statusChecks,
        1,
        reason: 'resolveIfIdle no-ops once resolved',
      );
      expect(find.text('Asha, 27'), findsOneWidget);
    });
  });
}

const _granted = LocationSuccess(
  latitude: 13.0827,
  longitude: 80.2707,
  accuracyMetres: 20,
);

/// Scrolls the section into view and taps its call to action.
///
/// `ensureVisible` rather than `scrollUntilVisible`: these slivers are not
/// lazy, so the finder matches immediately and `scrollUntilVisible` would stop
/// before scrolling, leaving the tap to land outside the viewport.
Future<void> _tapEnableLocation(WidgetTester tester) async {
  final button = find.text('Enable Location');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

List<Override> _overrides({
  required DeviceLocationService location,
  required NearbyRepository repository,
  required DiscoverFeedEntity feed,
}) => [
  deviceLocationServiceProvider.overrideWithValue(location),
  nearbyRepositoryProvider.overrideWithValue(repository),
  discoverFeedProvider.overrideWith((ref) async => feed),
];

Future<void> _pumpDiscover(
  WidgetTester tester, {
  required DeviceLocationService location,
  required NearbyRepository repository,
  DiscoverFeedEntity? feed,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        location: location,
        repository: repository,
        feed: feed ?? _feed(),
      ),
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DiscoverPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpWithContainer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DiscoverPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A feed with content, so Discover renders its normal sections.
DiscoverFeedEntity _feed() => DiscoverFeedEntity(
  stories: const [],
  profileCompletionPercent: 0,
  aiRecommended: [_profile(id: 'f1', name: 'Feed One', distanceKm: null)],
  recentlyJoined: const [],
  verifiedProfiles: const [],
  nearYou: const [],
  premiumMembers: const [],
);

/// Nothing matched the caller's saved preferences — the state that used to
/// take over the whole page.
DiscoverFeedEntity _emptyFeed() => const DiscoverFeedEntity(
  stories: [],
  profileCompletionPercent: 0,
  aiRecommended: [],
  recentlyJoined: [],
  verifiedProfiles: [],
  nearYou: [],
  premiumMembers: [],
);

DiscoveryProfileEntity _profile({
  required String id,
  required String name,
  required double? distanceKm,
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

/// Models the one thing that matters about the real service: WHEN a system
/// dialog appears.
///
/// [checkPermissionOnly] never shows one. [requestAndFetch] shows one only
/// when permission was not already granted — which mirrors geolocator, where
/// `requestPermission()` is called solely on a `denied` status. So
/// [promptsShown] counts exactly the dialogs a real user would have seen, and
/// [fixReads] counts GPS reads.
class _FakeLocationService implements DeviceLocationService {
  _FakeLocationService(this.result);

  LocationResult result;
  int statusChecks = 0;
  int fixReads = 0;
  int promptsShown = 0;

  @override
  Future<LocationResult?> checkPermissionOnly() async {
    statusChecks++;
    return result is LocationSuccess ? null : result;
  }

  @override
  Future<LocationResult> requestAndFetch() async {
    fixReads++;
    if (result is! LocationSuccess) promptsShown++;
    return result;
  }

  @override
  Future<bool> openLocationSettings() async => true;
}

class _FakeNearbyRepository implements NearbyRepository {
  _FakeNearbyRepository(this.profiles, {this.throwOnFetch = false});

  final List<DiscoveryProfileEntity> profiles;
  final bool throwOnFetch;

  int fetchCalls = 0;
  int updateLocationCalls = 0;

  @override
  Future<List<DiscoveryProfileEntity>> getNearbyProfiles({
    required double latitude,
    required double longitude,
    double radiusKm = 100,
    int page = 1,
    int limit = 50,
  }) async {
    fetchCalls++;
    if (throwOnFetch) throw Exception('network down');
    return profiles;
  }

  @override
  Future<void> updateMyLocation({
    required double latitude,
    required double longitude,
    int? accuracyMetres,
  }) async {
    updateLocationCalls++;
  }
}
