import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/services/location/device_location_service.dart';
import 'package:nenjam_matrimony/core/services/location/location_providers.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/compatibility_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/presentation/pages/discover_page.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/nearby/domain/repositories/nearby_repository.dart';
import 'package:nenjam_matrimony/features/nearby/presentation/providers/nearby_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The Discover card's Match/Astro stats row.
///
/// `astroMatchPercent == 0` means "not computed" — the astrology engine does
/// not exist yet, so `profile-feed.mapper.ts` sends a deliberate 0. The stats
/// row used to render it verbatim as "Astro 0%" next to a real AI score,
/// reading as a computed verdict of zero compatibility rather than an absent
/// one. `CompatibilityBadge` and `HoroscopeSection` already gate the same
/// value on `> 0`; these pin the stats row to that same rule.
void main() {
  /// The verified-profiles card is the one rendered with `showStats: true`.
  Future<void> pumpWithVerified(
    WidgetTester tester,
    DiscoveryProfileEntity profile,
  ) async {
    // Tall enough that the verified-profiles card builds without scrolling —
    // the feed's slivers are lazy, so a default 600px surface never reaches
    // it and every finder would report a false absence.
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceLocationServiceProvider.overrideWithValue(
            _FakeLocationService(),
          ),
          nearbyRepositoryProvider.overrideWithValue(_FakeNearbyRepository()),
          discoverFeedProvider.overrideWith(
            (ref) async => DiscoverFeedEntity(
              stories: const [],
              profileCompletionPercent: 0,
              aiRecommended: const [],
              recentlyJoined: const [],
              verifiedProfiles: [profile],
              nearYou: const [],
              premiumMembers: const [],
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DiscoverPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Sanity: the verified section must have rendered, or an absence
    // assertion below would pass for the wrong reason. Asserted on the
    // section heading rather than the member's name, which the card draws
    // through a styled span that `find.text` does not match.
    expect(find.text('Verified Profiles'), findsOneWidget);
  }

  DiscoveryProfileEntity profileWith({
    required int aiMatchPercent,
    required int astroMatchPercent,
  }) => DiscoveryProfileEntity(
    id: 'v1',
    matrimonyId: 'V1',
    name: 'Verified One',
    age: 27,
    location: 'Chennai',
    profession: 'Engineer',
    education: 'B.E.',
    photoUrls: const [],
    gender: 'Female',
    compatibility: CompatibilityEntity(
      aiMatchPercent: aiMatchPercent,
      astroMatchPercent: astroMatchPercent,
    ),
  );

  testWidgets('AI > 0 and Astro > 0 — both stats are shown', (tester) async {
    await pumpWithVerified(
      tester,
      profileWith(aiMatchPercent: 88, astroMatchPercent: 72),
    );

    expect(find.text('MATCH'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(find.text('ASTRO'), findsOneWidget);
    expect(find.text('72%'), findsOneWidget);
  });

  testWidgets('AI > 0 and Astro == 0 — AI shown, "Astro 0%" is not', (
    tester,
  ) async {
    await pumpWithVerified(
      tester,
      profileWith(aiMatchPercent: 88, astroMatchPercent: 0),
    );

    // The AI stat is untouched by this fix.
    expect(find.text('MATCH'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);

    // The regression: an uncomputed score must not render as a real one.
    expect(find.text('ASTRO'), findsNothing);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('AI == 0 — the row is absent entirely, as before', (
    tester,
  ) async {
    await pumpWithVerified(
      tester,
      profileWith(aiMatchPercent: 0, astroMatchPercent: 0),
    );

    // Pre-existing behaviour, unchanged: the whole row is gated on the AI
    // score upstream, so neither stat appears.
    expect(find.text('MATCH'), findsNothing);
    expect(find.text('ASTRO'), findsNothing);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('AI == 0 with a real Astro score — row still absent', (
    tester,
  ) async {
    await pumpWithVerified(
      tester,
      profileWith(aiMatchPercent: 0, astroMatchPercent: 72),
    );

    // The outer gate is the AI score and this fix does not change it.
    expect(find.text('MATCH'), findsNothing);
    expect(find.text('ASTRO'), findsNothing);
  });
}

class _FakeLocationService implements DeviceLocationService {
  @override
  Future<LocationResult> checkPermissionOnly() async =>
      const LocationPermissionDenied();

  @override
  Future<LocationResult> requestAndFetch() async =>
      const LocationPermissionDenied();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNearbyRepository implements NearbyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
