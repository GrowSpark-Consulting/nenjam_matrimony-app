import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/services/location/device_location_service.dart';
import 'package:nenjam_matrimony/core/services/location/location_providers.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/story_entity.dart';
import 'package:nenjam_matrimony/features/discover/presentation/pages/discover_page.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/nearby/domain/repositories/nearby_repository.dart';
import 'package:nenjam_matrimony/features/nearby/presentation/providers/nearby_providers.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/profile_completion/domain/completion_recommendation.dart';
import 'package:nenjam_matrimony/features/profile_completion/presentation/widgets/complete_profile_card.dart';
import 'package:nenjam_matrimony/features/profile_photos/domain/models/user_photo.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/widgets/photo_manager_section.dart'
    show kMaxPhotos;
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The "Complete Your Profile" card is a Home-level component, not a feed
/// section.
///
/// It first shipped nested inside Discover's non-empty-feed branch, so a
/// member with nothing matching their filters — the exact member most worth
/// nudging — saw "No matching profiles found" and no card at all. These pin
/// that its visibility follows the profile-completion response and nothing
/// about the match results.

// ─── Fixtures ────────────────────────────────────────────────────────────

DiscoveryProfileEntity _profile(String id, String name) =>
    DiscoveryProfileEntity(
      id: id,
      matrimonyId: id,
      name: name,
      age: 27,
      height: "5'4\"",
      profession: 'Engineer',
      location: 'Chennai',
      education: 'B.E',
      photoUrls: const [],
      religion: 'Hindu',
      caste: 'Iyer',
      motherTongue: 'Tamil',
      gender: 'Female',
    );

/// Zero profiles in every section — what the backend returns when nothing
/// matches the member's filters. Discover renders its empty state for this.
const _emptyFeed = DiscoverFeedEntity(
  stories: [],
  profileCompletionPercent: 0,
  aiRecommended: [],
  recentlyJoined: [],
  verifiedProfiles: [],
  nearYou: [],
  premiumMembers: [],
  fallbackReason: 'NO_MATCHES',
);

DiscoverFeedEntity _populatedFeed() => DiscoverFeedEntity(
  stories: [
    StoryEntity(
      id: 's1',
      name: 'Janani',
      imageUrl: '',
      hasNewStory: true,
      gender: 'Female',
      profile: _profile('s1', 'Janani'),
    ),
  ],
  profileCompletionPercent: 0,
  aiRecommended: [_profile('a1', 'Deepika')],
  recentlyJoined: [_profile('r1', 'Meera')],
  verifiedProfiles: [_profile('v1', 'Sowmya')],
  nearYou: const [],
  premiumMembers: [_profile('p1', 'Lakshmi')],
);

Map<String, dynamic> _card(
  String key, {
  bool isComplete = false,
  required int wizardStep,
}) => <String, dynamic>{
  'key': key,
  'isComplete': isComplete,
  'isDismissed': false,
  'affectsScore': false,
  'wizardStep': wizardStep,
};

Map<String, dynamic> _draft({bool allComplete = false}) => <String, dynamic>{
  'completionPercentage': allComplete ? 100 : 65,
  'completionBreakdown': const [
    {'id': 'registration', 'weight': 60, 'isComplete': true, 'wizardStep': 0},
  ],
  'registrationComplete': true,
  'recommendations': [
    _card(CompletionCardKeys.aboutFamily, isComplete: allComplete, wizardStep: 7),
    _card(CompletionCardKeys.horoscope, isComplete: allComplete, wizardStep: 8),
    _card(CompletionCardKeys.psychology, isComplete: allComplete, wizardStep: 9),
    _card(
      CompletionCardKeys.partnerPreference,
      isComplete: allComplete,
      wizardStep: 10,
    ),
  ],
};

// ─── Fakes ───────────────────────────────────────────────────────────────

class _SilentLocationService implements DeviceLocationService {
  @override
  Future<LocationResult?> checkPermissionOnly() async =>
      const LocationPermissionDenied();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyNearbyRepository implements NearbyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRegistrationRepository implements RegistrationRepository {
  @override
  Future<Map<String, dynamic>> getDraft() async => <String, dynamic>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePhotosController extends PhotosController {
  @override
  // Photos already at the cap by default — these tests are about the feed
  // and the four backend-scored sections, not the photo tile (that's
  // exercised in complete_profile_card_test.dart).
  Future<List<UserPhoto>> build() async => List.generate(
    kMaxPhotos,
    (i) => UserPhoto(
      id: 'photo-$i',
      cdnUrl: '',
      isPrimary: i == 0,
      order: i,
      isApproved: true,
    ),
  );
}

// ─── Harness ─────────────────────────────────────────────────────────────

Future<void> _pumpDiscover(
  WidgetTester tester, {
  required DiscoverFeedEntity feed,
  required Map<String, dynamic> draft,
  Size surface = const Size(1080, 2400),
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        discoverFeedProvider.overrideWith((ref) async => feed),
        profileDraftResponseProvider.overrideWith((ref) async => draft),
        registrationRepositoryProvider.overrideWithValue(
          _FakeRegistrationRepository(),
        ),
        deviceLocationServiceProvider.overrideWithValue(
          _SilentLocationService(),
        ),
        nearbyRepositoryProvider.overrideWithValue(_EmptyNearbyRepository()),
        myPhotosProvider.overrideWith(_FakePhotosController.new),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DiscoverPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the card does not depend on the feed having matches', () {
    testWidgets(
      'an empty feed still shows the card — the regression this fixes',
      (tester) async {
        await _pumpDiscover(tester, feed: _emptyFeed, draft: _draft());

        // The card, in full.
        expect(find.text('Complete Your Profile'), findsOneWidget);
        expect(
          find.text('Get better matches by adding a few more details'),
          findsOneWidget,
        );
        expect(find.text('Family Details'), findsOneWidget);
        expect(find.text('Horoscope'), findsOneWidget);
        expect(find.text('Psychology'), findsOneWidget);
        expect(find.text('Partner Preferences'), findsOneWidget);
      },
    );

    testWidgets('the empty state is still shown alongside it, unchanged', (
      tester,
    ) async {
      await _pumpDiscover(tester, feed: _emptyFeed, draft: _draft());

      // The card was added to the empty state, not in place of it.
      expect(find.text('Complete Your Profile'), findsOneWidget);
      expect(find.byIcon(Icons.travel_explore_rounded), findsOneWidget);
      expect(find.text('Near You'), findsOneWidget);
    });

    testWidgets('the card sits above the empty state, not below it', (
      tester,
    ) async {
      await _pumpDiscover(tester, feed: _emptyFeed, draft: _draft());

      final cardTop = tester.getTopLeft(find.byType(CompleteProfileCard)).dy;
      final emptyStateTop = tester
          .getTopLeft(find.byIcon(Icons.travel_explore_rounded))
          .dy;
      expect(cardTop, lessThan(emptyStateTop));
    });

    testWidgets('a populated feed shows the card too', (tester) async {
      await _pumpDiscover(tester, feed: _populatedFeed(), draft: _draft());

      expect(find.text('Complete Your Profile'), findsOneWidget);
      expect(find.text('Family Details'), findsOneWidget);
    });

    testWidgets(
      'on a populated feed it sits between the stories and AI Recommended',
      (tester) async {
        await _pumpDiscover(tester, feed: _populatedFeed(), draft: _draft());

        final storiesTop = tester.getTopLeft(find.text('Janani')).dy;
        final cardTop = tester.getTopLeft(find.byType(CompleteProfileCard)).dy;
        final aiTop = tester.getTopLeft(find.text('AI Recommended')).dy;

        expect(storiesTop, lessThan(cardTop));
        expect(cardTop, lessThan(aiTop));
      },
    );
  });

  group('completion state still governs the card', () {
    testWidgets('all four complete hides it on an empty feed', (tester) async {
      await _pumpDiscover(
        tester,
        feed: _emptyFeed,
        draft: _draft(allComplete: true),
      );

      expect(find.text('Complete Your Profile'), findsNothing);
      expect(find.text('Family Details'), findsNothing);
      // ...and the feed's own empty state is untouched by its absence.
      expect(find.byIcon(Icons.travel_explore_rounded), findsOneWidget);
    });

    testWidgets('all four complete hides it on a populated feed', (
      tester,
    ) async {
      await _pumpDiscover(
        tester,
        feed: _populatedFeed(),
        draft: _draft(allComplete: true),
      );

      expect(find.text('Complete Your Profile'), findsNothing);
      expect(find.text('AI Recommended'), findsOneWidget);
    });

    testWidgets('dismissing it on an empty feed leaves the feed alone', (
      tester,
    ) async {
      await _pumpDiscover(tester, feed: _emptyFeed, draft: _draft());

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Complete Your Profile'), findsNothing);
      // The empty state and Near You are exactly where they were.
      expect(find.byIcon(Icons.travel_explore_rounded), findsOneWidget);
      expect(find.text('Near You'), findsOneWidget);
    });
  });

  group('narrow screens', () {
    testWidgets('no overflow with four tiles over an empty feed', (
      tester,
    ) async {
      await _pumpDiscover(
        tester,
        feed: _emptyFeed,
        draft: _draft(),
        surface: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Complete Your Profile'), findsOneWidget);
    });
  });
}
