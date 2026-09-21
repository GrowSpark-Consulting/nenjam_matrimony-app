import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
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

/// Home/Discover's compact "Complete Your Profile" reminder — the
/// whole-card-dismissible sibling of `CompleteProfileSection`, offering up
/// to five tiles: Add Photos, Family Details, Horoscope, Psychology and
/// Partner Preferences.
///
/// Four of the five read the exact same `GET /profiles/draft` response the
/// full section reads (via [profileDraftResponseProvider] /
/// [profileCompletenessSnapshotProvider]). Photos is the one exception —
/// it reads the live photo count off [myPhotosProvider], the same provider
/// every other photo UI in the app uses, and completes at [kMaxPhotos]
/// rather than the backend's registration-minimum "at least one" bar. These
/// tests fix both sources and assert what the card does with them — never a
/// second, invented completion signal.

// ─── Fixtures ────────────────────────────────────────────────────────────

Map<String, dynamic> _card(
  String key, {
  bool isComplete = false,
  required int wizardStep,
  bool affectsScore = true,
}) => <String, dynamic>{
  'key': key,
  'isComplete': isComplete,
  'isDismissed': false,
  'affectsScore': affectsScore,
  'wizardStep': wizardStep,
};

Map<String, dynamic> _draft({
  bool familyComplete = false,
  bool horoscopeComplete = false,
  bool psychologyComplete = false,
  bool partnerPreferenceComplete = false,
}) => <String, dynamic>{
  'completionPercentage': 65,
  'completionBreakdown': const [
    {'id': 'registration', 'weight': 60, 'isComplete': true, 'wizardStep': 0},
  ],
  'registrationComplete': true,
  'recommendations': [
    _card(CompletionCardKeys.registration, isComplete: true, wizardStep: 0),
    _card(
      CompletionCardKeys.aboutFamily,
      isComplete: familyComplete,
      wizardStep: 7,
    ),
    _card(
      CompletionCardKeys.horoscope,
      isComplete: horoscopeComplete,
      wizardStep: 8,
    ),
    _card(
      CompletionCardKeys.psychology,
      isComplete: psychologyComplete,
      affectsScore: false,
      wizardStep: 9,
    ),
    _card(
      CompletionCardKeys.partnerPreference,
      isComplete: partnerPreferenceComplete,
      affectsScore: false,
      wizardStep: 10,
    ),
    // Verification is deliberately part of the same response but never a
    // tile on this card — proves the filter, not just an absent fixture.
    _card(CompletionCardKeys.verification, wizardStep: 12),
  ],
};

List<UserPhoto> _photos(int count) => List.generate(
  count,
  (i) => UserPhoto(
    id: 'photo-$i',
    cdnUrl: '',
    isPrimary: i == 0,
    order: i,
    isApproved: true,
  ),
);

// ─── Fakes ───────────────────────────────────────────────────────────────

class _FakeRegistrationRepository implements RegistrationRepository {
  @override
  Future<Map<String, dynamic>> getDraft() async => <String, dynamic>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePhotosController extends PhotosController {
  _FakePhotosController(this._photos);
  final List<UserPhoto> _photos;

  @override
  Future<List<UserPhoto>> build() async => _photos;
}

// ─── Harness ─────────────────────────────────────────────────────────────

class _Harness {
  late final ProviderContainer container;
  late final GoRouter router;
  Map<String, dynamic> draft;
  int draftFetches = 0;

  /// Defaults to a full 6 photos — Photos already complete — so tests that
  /// only care about the four backend-scored sections see exactly those
  /// four, unless a test explicitly exercises photo counts.
  final int photoCount;

  _Harness(this.draft, {this.photoCount = kMaxPhotos});

  Future<void> pump(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        profileDraftResponseProvider.overrideWith((ref) async {
          draftFetches++;
          return draft;
        }),
        registrationRepositoryProvider.overrideWithValue(
          _FakeRegistrationRepository(),
        ),
        myPhotosProvider.overrideWith(
          () => _FakePhotosController(_photos(photoCount)),
        ),
      ],
    );
    addTearDown(container.dispose);

    Widget page(Widget child) =>
        Scaffold(body: SingleChildScrollView(child: child));

    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => page(const CompleteProfileCard()),
        ),
        GoRoute(
          path: RouteNames.profileEdit,
          builder: (_, state) => page(
            Text(
              'EDIT PROFILE section=${state.uri.queryParameters['section']}',
            ),
          ),
        ),
        GoRoute(
          path: RouteNames.psychologyQuiz,
          builder: (_, _) => page(const Text('PSYCHOLOGY QUIZ PAGE')),
        ),
        GoRoute(
          path: RouteNames.partnerPreferences,
          builder: (_, _) => page(const Text('PARTNER PREFERENCES PAGE')),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> refreshWith(WidgetTester tester, Map<String, dynamic> next) async {
    draft = next;
    container.invalidate(profileDraftResponseProvider);
    await tester.pumpAndSettle();
  }
}

List<String> _tileTitles(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(CompleteProfileCard),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data)
    .whereType<String>()
    .toList();

void main() {
  group('the four backend-scored sections, photos already complete', () {
    testWidgets('shows exactly the four tiles, and no others', (
      tester,
    ) async {
      await _Harness(_draft()).pump(tester);

      final titles = _tileTitles(tester);
      expect(titles, contains('Family Details'));
      expect(titles, contains('Horoscope'));
      expect(titles, contains('Psychology'));
      expect(titles, contains('Partner Preferences'));
      expect(titles, isNot(contains('Add Photos')));
      // The response carries a verification card too — proves the card
      // filters to its keys rather than drawing everything it is given.
      expect(titles, isNot(contains('Verification')));
      expect(titles, isNot(contains('Finish Registration')));
    });

    testWidgets('shows the header and subtitle', (tester) async {
      await _Harness(_draft()).pump(tester);

      expect(find.text('Complete Your Profile'), findsOneWidget);
      expect(
        find.text('Get better matches by adding a few more details'),
        findsOneWidget,
      );
    });
  });

  group('a completed section drops only its own tile', () {
    testWidgets('family complete removes the Family Details tile', (
      tester,
    ) async {
      await _Harness(_draft(familyComplete: true)).pump(tester);

      final titles = _tileTitles(tester);
      expect(titles, isNot(contains('Family Details')));
      expect(titles, contains('Horoscope'));
      expect(titles, contains('Psychology'));
      expect(titles, contains('Partner Preferences'));
    });

    testWidgets('horoscope complete removes the Horoscope tile', (
      tester,
    ) async {
      await _Harness(_draft(horoscopeComplete: true)).pump(tester);

      final titles = _tileTitles(tester);
      expect(titles, isNot(contains('Horoscope')));
      expect(titles, contains('Family Details'));
      expect(titles, contains('Psychology'));
      expect(titles, contains('Partner Preferences'));
    });

    testWidgets('psychology complete removes the Psychology tile', (
      tester,
    ) async {
      await _Harness(_draft(psychologyComplete: true)).pump(tester);

      final titles = _tileTitles(tester);
      expect(titles, isNot(contains('Psychology')));
      expect(titles, contains('Family Details'));
      expect(titles, contains('Horoscope'));
      expect(titles, contains('Partner Preferences'));
    });

    testWidgets(
      'partner preference complete removes the Partner Preferences tile',
      (tester) async {
        await _Harness(_draft(partnerPreferenceComplete: true)).pump(tester);

        final titles = _tileTitles(tester);
        expect(titles, isNot(contains('Partner Preferences')));
        expect(titles, contains('Family Details'));
        expect(titles, contains('Horoscope'));
        expect(titles, contains('Psychology'));
      },
    );
  });

  group('Add Photos tracks the real photo count', () {
    testWidgets('0 photos shows Add Photos', (tester) async {
      await _Harness(_draft(), photoCount: 0).pump(tester);
      expect(find.text('Add Photos'), findsOneWidget);
    });

    testWidgets('5 photos still shows Add Photos', (tester) async {
      await _Harness(_draft(), photoCount: 5).pump(tester);
      expect(find.text('Add Photos'), findsOneWidget);
    });

    testWidgets('6 photos (kMaxPhotos) hides Add Photos', (tester) async {
      await _Harness(_draft(), photoCount: kMaxPhotos).pump(tester);
      expect(find.text('Add Photos'), findsNothing);
    });

    testWidgets('Add Photos appears first, alongside the other tiles', (
      tester,
    ) async {
      await _Harness(_draft(), photoCount: 2).pump(tester);

      final titles = _tileTitles(tester)
          .where((t) => t != 'Complete Your Profile')
          .where((t) => t != 'Get better matches by adding a few more details')
          .toList();
      expect(titles.first, 'Add Photos');
      expect(titles, containsAll(['Family Details', 'Horoscope', 'Psychology', 'Partner Preferences']));
    });

    testWidgets('uploading photos up to the cap and returning hides the '
        'tile after refresh', (tester) async {
      final harness = _Harness(_draft(), photoCount: 5);
      await harness.pump(tester);
      expect(find.text('Add Photos'), findsOneWidget);

      // Simulate PhotosController publishing the 6th photo directly —
      // exactly how a real upload updates this same provider — with no
      // extra refresh call from this card, since it already watches
      // myPhotosProvider live.
      harness.container
          .read(myPhotosProvider.notifier)
          .state = AsyncValue.data(_photos(kMaxPhotos));
      await tester.pumpAndSettle();

      expect(find.text('Add Photos'), findsNothing);
    });
  });

  group('all five complete', () {
    testWidgets('the whole card disappears, not just its tiles', (
      tester,
    ) async {
      await _Harness(
        _draft(
          familyComplete: true,
          horoscopeComplete: true,
          psychologyComplete: true,
          partnerPreferenceComplete: true,
        ),
        // Already defaults to kMaxPhotos (complete).
      ).pump(tester);

      expect(find.byType(CompleteProfileCard), findsOneWidget);
      expect(find.text('Complete Your Profile'), findsNothing);
      expect(find.text('Add Photos'), findsNothing);
      expect(find.text('Family Details'), findsNothing);
      expect(find.text('Horoscope'), findsNothing);
      expect(find.text('Psychology'), findsNothing);
      expect(find.text('Partner Preferences'), findsNothing);
    });

    testWidgets('completing the last section removes the card on refresh', (
      tester,
    ) async {
      final harness = _Harness(
        _draft(
          familyComplete: true,
          horoscopeComplete: true,
          psychologyComplete: true,
        ),
      );
      await harness.pump(tester);
      expect(find.text('Partner Preferences'), findsOneWidget);

      await harness.refreshWith(
        tester,
        _draft(
          familyComplete: true,
          horoscopeComplete: true,
          psychologyComplete: true,
          partnerPreferenceComplete: true,
        ),
      );

      expect(find.text('Complete Your Profile'), findsNothing);
    });
  });

  group('tapping a tile opens the matching existing flow', () {
    Future<void> expectTapOpens(
      WidgetTester tester,
      String cardKey,
      String expectedPage, {
      int photoCount = kMaxPhotos,
    }) async {
      final harness = _Harness(_draft(), photoCount: photoCount);
      await harness.pump(tester);

      await tester.tap(find.byKey(ValueKey('home-complete-profile-$cardKey')));
      await tester.pumpAndSettle();

      expect(find.text(expectedPage), findsOneWidget);
      expect(find.byType(CompleteProfileCard), findsNothing);
    }

    testWidgets('Add Photos opens Edit Profile at the photos step', (
      tester,
    ) async {
      await expectTapOpens(
        tester,
        CompletionCardKeys.photo,
        'EDIT PROFILE section=11',
        photoCount: 0,
      );
    });

    testWidgets('Family Details opens Edit Profile at the family section', (
      tester,
    ) async {
      await expectTapOpens(
        tester,
        CompletionCardKeys.aboutFamily,
        'EDIT PROFILE section=7',
      );
    });

    testWidgets('Horoscope opens Edit Profile at the horoscope section', (
      tester,
    ) async {
      await expectTapOpens(
        tester,
        CompletionCardKeys.horoscope,
        'EDIT PROFILE section=8',
      );
    });

    testWidgets('Psychology opens the psychology quiz', (tester) async {
      await expectTapOpens(
        tester,
        CompletionCardKeys.psychology,
        'PSYCHOLOGY QUIZ PAGE',
      );
    });

    testWidgets('Partner Preferences opens the partner preferences page', (
      tester,
    ) async {
      await expectTapOpens(
        tester,
        CompletionCardKeys.partnerPreference,
        'PARTNER PREFERENCES PAGE',
      );
    });

    testWidgets('opening a tile refreshes completion state', (tester) async {
      final harness = _Harness(_draft());
      await harness.pump(tester);
      final fetchesBeforeTap = harness.draftFetches;

      await tester.tap(
        find.byKey(
          const ValueKey(
            'home-complete-profile-${CompletionCardKeys.aboutFamily}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // `_open` calls refreshProfileCompletion, which invalidates the same
      // draft provider Home and Edit Profile both read — a second fetch
      // proves the card asked for fresh completion state rather than
      // leaving the stale response in place.
      expect(harness.draftFetches, greaterThan(fetchesBeforeTap));
    });
  });

  group('dismissing the whole card', () {
    testWidgets('the close button hides the card entirely', (tester) async {
      await _Harness(_draft()).pump(tester);
      expect(find.byType(CompleteProfileCard), findsOneWidget);
      expect(find.text('Complete Your Profile'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Complete Your Profile'), findsNothing);
      expect(find.text('Family Details'), findsNothing);
    });

    testWidgets('dismissing never touches completion data', (tester) async {
      final harness = _Harness(_draft());
      await harness.pump(tester);
      final fetchesBeforeDismiss = harness.draftFetches;

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // No section became complete and no extra fetch was made — dismissal
      // is a purely local UI flag, never a write against profile data.
      expect(harness.draftFetches, fetchesBeforeDismiss);
      expect(harness.draft, _draft());
    });

    testWidgets(
      'a section actually finishing while dismissed stays hidden, not '
      'brought back by the completion, proving dismiss and completion are '
      'independent flags',
      (tester) async {
        final harness = _Harness(_draft());
        await harness.pump(tester);

        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(CompleteProfileCard), findsOneWidget);
        expect(find.text('Complete Your Profile'), findsNothing);

        await harness.refreshWith(tester, _draft(familyComplete: true));

        // Still dismissed — completing a section must not un-dismiss the
        // card the member already closed this session.
        expect(find.text('Complete Your Profile'), findsNothing);
        expect(find.text('Horoscope'), findsNothing);
      },
    );
  });

  group('horizontal scrolling', () {
    testWidgets('a scroller holds the tiles, not an evenly-split row', (
      tester,
    ) async {
      await _Harness(_draft(), photoCount: 0).pump(tester);

      final scrollable = find.descendant(
        of: find.byType(CompleteProfileCard),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollable, findsOneWidget);
      expect(
        tester.widget<SingleChildScrollView>(scrollable).scrollDirection,
        Axis.horizontal,
      );
    });

    testWidgets('all five tiles are reachable by scrolling', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _Harness(_draft(), photoCount: 0).pump(tester);

      final lastTile = find.byKey(
        const ValueKey(
          'home-complete-profile-${CompletionCardKeys.partnerPreference}',
        ),
      );

      await tester.dragUntilVisible(
        lastTile,
        find.descendant(
          of: find.byType(CompleteProfileCard),
          matching: find.byType(SingleChildScrollView),
        ),
        const Offset(-40, 0),
      );
      await tester.pumpAndSettle();

      expect(lastTile, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('narrow screens', () {
    testWidgets('five tiles never overflow the layout', (tester) async {
      // The narrowest phone width the app's responsive audit covers.
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _Harness(_draft(), photoCount: 0).pump(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Add Photos'), findsOneWidget);
      expect(find.text('Family Details'), findsOneWidget);
      expect(find.text('Horoscope'), findsOneWidget);
      expect(find.text('Psychology'), findsOneWidget);
      expect(find.text('Partner Preferences'), findsOneWidget);
    });
  });

  group('nothing to show yet', () {
    testWidgets('renders nothing while completion data has not loaded', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          // Never resolves within this test — the widget must stay inert,
          // not throw or show a placeholder.
          profileDraftResponseProvider.overrideWith(
            (ref) => Completer<Map<String, dynamic>>().future,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: CompleteProfileCard()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Complete Your Profile'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
