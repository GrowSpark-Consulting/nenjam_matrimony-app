import 'dart:io';

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
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Discover's landing must be the same for everyone — including the member who
/// arrives on it seconds after finishing registration.
///
/// It previously was not. The backend reports `INCOMPLETE_SELF_PROFILE` when
/// the caller has no finalized profile, and Discover turned that into a
/// full-screen "Complete Your Profile" / "Complete Your Story" prompt. A
/// freshly-registered member therefore met a completion call to action instead
/// of the Discover page.
///
/// These pin that the prompt is gone for good, and — just as importantly —
/// that nothing else on Discover moved to achieve it.
void main() {
  DiscoveryProfileEntity profile(String id, String name) =>
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

  StoryEntity story(String id, String name) => StoryEntity(
        id: id,
        name: name,
        imageUrl: '',
        hasNewStory: true,
        gender: 'Female',
        profile: profile(id, name),
      );

  /// A populated feed — the normal Discover landing, every section filled so
  /// that "the rest of Discover is untouched" can be asserted section by
  /// section rather than inferred from one of them.
  DiscoverFeedEntity populated() => DiscoverFeedEntity(
        stories: [
          story('s1', 'Janani'),
          story('s2', 'Yamuna'),
          story('s3', 'Kavipriya'),
          story('s4', 'Ananya'),
        ],
        profileCompletionPercent: 0,
        aiRecommended: [profile('a1', 'Deepika')],
        recentlyJoined: [profile('r1', 'Meera'), profile('r2', 'Divya')],
        verifiedProfiles: [profile('v1', 'Sowmya')],
        nearYou: const [],
        premiumMembers: [profile('p1', 'Lakshmi')],
      );

  /// Exactly what the backend returns to a member who has just registered but
  /// whose profile has not finalized: nothing, with the reason spelled out.
  const justRegistered = DiscoverFeedEntity(
    stories: [],
    profileCompletionPercent: 0,
    aiRecommended: [],
    recentlyJoined: [],
    verifiedProfiles: [],
    nearYou: [],
    premiumMembers: [],
    fallbackReason: 'INCOMPLETE_SELF_PROFILE',
  );

  Future<void> pumpDiscover(
    WidgetTester tester,
    DiscoverFeedEntity feed, {
    Size surface = const Size(1080, 2400),
    List<NavigatorObserver> observers = const [],
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discoverFeedProvider.overrideWith((ref) async => feed),
          deviceLocationServiceProvider
              .overrideWithValue(_SilentLocationService()),
          nearbyRepositoryProvider.overrideWithValue(_EmptyNearbyRepository()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: observers,
          home: const DiscoverPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every string and control the removed completion prompt used to render.
  void expectNoCompletionPrompt(WidgetTester tester) {
    expect(find.text('Complete Your Profile'), findsNothing);
    expect(find.text('Complete Your Story'), findsNothing);
    expect(
      find.text('Every detail helps us find your best match.'),
      findsNothing,
    );
    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsNothing);
    // And no prompt was raised over the page either.
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  }

  group('straight after registration', () {
    testWidgets('no Complete Your Profile prompt on the Discover landing', (
      tester,
    ) async {
      // The exact state a member is in the moment registration navigates them
      // to Discover.
      await pumpDiscover(tester, justRegistered);

      expectNoCompletionPrompt(tester);
    });

    testWidgets('no completion prompt is raised as a popup or sheet', (
      tester,
    ) async {
      await pumpDiscover(tester, justRegistered);

      // Nothing on Discover opens a dialog or sheet on arrival — there is no
      // initState hook, post-frame callback or route observer that could.
      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('Discover never navigates away on its own', (tester) async {
      // The other half of the old behaviour: not just the prompt, but the
      // route it pushed. An incomplete profile must not bounce the member to
      // Edit Profile — landing on Discover has to leave them on Discover.
      final observer = _RouteRecorder();
      await pumpDiscover(tester, justRegistered, observers: [observer]);

      // Settled, and then some: a delayed post-frame redirect would have
      // fired by now.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(
        observer.pushesAfterFirst,
        isEmpty,
        reason: 'Discover pushed ${observer.pushesAfterFirst} unprompted',
      );
      expect(find.byType(DiscoverPage), findsOneWidget);
    });

    testWidgets('the generic empty state is shown instead, not a blank page', (
      tester,
    ) async {
      await pumpDiscover(tester, justRegistered);

      // Removing the prompt must not leave the member staring at nothing:
      // the plain "nothing matched yet" state that already existed for every
      // other empty-feed cause now covers this one too.
      expect(find.byType(ElevatedButton), findsWidgets);
      expect(find.byIcon(Icons.travel_explore_rounded), findsOneWidget);
    });
  });

  group('an already-registered member', () {
    testWidgets('sees no completion prompt on a populated feed', (
      tester,
    ) async {
      await pumpDiscover(tester, populated());

      expectNoCompletionPrompt(tester);
    });

    testWidgets('still sees the whole existing Discover landing', (
      tester,
    ) async {
      await pumpDiscover(tester, populated());

      // The story rings, untouched.
      for (final name in ['Janani', 'Yamuna', 'Kavipriya', 'Ananya']) {
        expect(find.text(name), findsOneWidget, reason: '$name went missing');
      }
      // The recommendation content, untouched.
      expect(find.text('AI Recommended'), findsOneWidget);
      expect(find.textContaining('Deepika'), findsWidgets);
      // And the remaining sections, which sit below the fold on a phone —
      // scrolled to rather than dropped, since "the rest of Discover is still
      // there" is exactly what this is asserting.
      for (final title in [
        'Recently Joined',
        'Verified Profiles',
        'Near You',
        'Premium Members',
      ]) {
        await tester.scrollUntilVisible(
          find.text(title),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(title), findsOneWidget, reason: '$title went missing');
      }
    });

    testWidgets('the story rings still come first, directly under the bar', (
      tester,
    ) async {
      await pumpDiscover(tester, populated());

      // Nothing was inserted above the rings to replace what was removed.
      final storiesTop = tester.getTopLeft(find.text('Janani')).dy;
      final aiTop = tester.getTopLeft(find.text('AI Recommended')).dy;
      expect(storiesTop, lessThan(aiTop));
    });
  });

  group('the other empty-feed cause is unchanged', () {
    testWidgets('a finalized member with no matches keeps its own message', (
      tester,
    ) async {
      const noMatches = DiscoverFeedEntity(
        stories: [],
        profileCompletionPercent: 0,
        aiRecommended: [],
        recentlyJoined: [],
        verifiedProfiles: [],
        nearYou: [],
        premiumMembers: [],
        fallbackReason: 'NO_MATCHES',
      );

      await pumpDiscover(tester, noMatches);

      // This path never showed a completion prompt and still does not; it is
      // the message the profile-completion branch now falls back to.
      expectNoCompletionPrompt(tester);
      expect(find.byIcon(Icons.travel_explore_rounded), findsOneWidget);
    });
  });

  group('the source itself', () {
    // Widget tests can only prove the prompt is absent for the feeds they
    // pump. These prove the wiring that produced it is gone, so it cannot
    // come back through a state nobody thought to write a test for.
    final discover = File(
      'lib/features/discover/presentation/pages/discover_page.dart',
    ).readAsStringSync();

    // Doc comments explain why the branch was removed; only executable code
    // is under test here.
    final code = discover
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('carries no profile-completion UI', () {
      expect(code, isNot(contains('CompleteProfileSection')));
      expect(code, isNot(contains('homeCompleteProfileTitle')));
      expect(code, isNot(contains('profileCompletionTipRegistration')));
      expect(code, isNot(contains('profileCompletionActionRegistration')));
    });

    test('never branches on INCOMPLETE_SELF_PROFILE', () {
      expect(code, isNot(contains('INCOMPLETE_SELF_PROFILE')));
    });

    test('has no route to Edit Profile', () {
      expect(code, isNot(contains('openEditProfile')));
      expect(code, isNot(contains('open_edit_profile')));
      expect(code, isNot(contains('RouteNames.editProfile')));
    });
  });
}

/// Records every route pushed after the initial one, so a test can assert
/// Discover navigated nowhere by itself.
class _RouteRecorder extends NavigatorObserver {
  final List<String> _pushed = [];

  List<String> get pushesAfterFirst =>
      _pushed.length <= 1 ? const [] : _pushed.sublist(1);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pushed.add(route.settings.name ?? route.runtimeType.toString());
  }
}

/// Reports "denied" without raising a dialog, so Near You renders its inline
/// CTA and no system prompt blocks the test.
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
