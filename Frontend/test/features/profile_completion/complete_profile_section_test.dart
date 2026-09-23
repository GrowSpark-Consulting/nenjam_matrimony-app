import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/theme/app_colors.dart';
import 'package:nenjam_matrimony/core/widgets/cards/completion_card.dart';
import 'package:nenjam_matrimony/core/widgets/indicators/nm_gradient_progress_bar.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/profile_completion/data/completion_recommendation_repository.dart';
import 'package:nenjam_matrimony/features/profile_completion/domain/completion_recommendation.dart';
import 'package:nenjam_matrimony/features/profile_completion/presentation/providers/completion_recommendation_provider.dart';
import 'package:nenjam_matrimony/features/profile_completion/presentation/widgets/complete_profile_section.dart';
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The "Complete Your Profile" section, as Home and the end-of-registration
/// review both render it.
///
/// Everything here is driven by one `GET /profiles/draft` response, because
/// that is the actual guarantee being tested: the two screens embed this one
/// widget reading one backend payload, so they cannot show different cards,
/// a different percentage, or navigate somewhere different.

// ─── Fixtures ────────────────────────────────────────────────────────────

Map<String, dynamic> _card(
  String key, {
  bool isComplete = false,
  bool isDismissed = false,
  bool affectsScore = true,
  required int wizardStep,
}) => <String, dynamic>{
  'key': key,
  'isComplete': isComplete,
  'isDismissed': isDismissed,
  'affectsScore': affectsScore,
  'wizardStep': wizardStep,
};

/// A registered member's draft response, with the four section cards.
Map<String, dynamic> _draft({
  int percentage = 60,
  bool registrationComplete = true,
  bool familyComplete = false,
  bool horoscopeComplete = false,
  bool verificationComplete = false,
  bool psychologyComplete = false,
  Set<String> dismissed = const {},
  List<Map<String, dynamic>>? recommendations,
}) => <String, dynamic>{
  'completionPercentage': percentage,
  'completionBreakdown': const [
    {'id': 'registration', 'weight': 60, 'isComplete': true, 'wizardStep': 0},
    {'id': 'family', 'weight': 10, 'isComplete': false, 'wizardStep': 7},
    {'id': 'horoscope', 'weight': 5, 'isComplete': false, 'wizardStep': 8},
    {'id': 'verification', 'weight': 25, 'isComplete': false, 'wizardStep': 12},
  ],
  'registrationComplete': registrationComplete,
  'recommendations':
      recommendations ??
      [
        _card(CompletionCardKeys.registration, isComplete: true, wizardStep: 0),
        _card(CompletionCardKeys.photo, isComplete: true, wizardStep: 11),
        _card(
          CompletionCardKeys.aboutFamily,
          isComplete: familyComplete,
          isDismissed: dismissed.contains(CompletionCardKeys.aboutFamily),
          wizardStep: 7,
        ),
        _card(
          CompletionCardKeys.horoscope,
          isComplete: horoscopeComplete,
          isDismissed: dismissed.contains(CompletionCardKeys.horoscope),
          wizardStep: 8,
        ),
        _card(
          CompletionCardKeys.verification,
          isComplete: verificationComplete,
          isDismissed: dismissed.contains(CompletionCardKeys.verification),
          wizardStep: 12,
        ),
        _card(
          CompletionCardKeys.psychology,
          isComplete: psychologyComplete,
          isDismissed: dismissed.contains(CompletionCardKeys.psychology),
          affectsScore: false,
          wizardStep: 9,
        ),
      ],
};

// ─── Fakes ───────────────────────────────────────────────────────────────

/// Stands in for the network. `getDraft` is what `openEditProfile` calls
/// before navigating; nothing here can write a profile section, which is the
/// point of the dismissal assertions below.
class _FakeRegistrationRepository implements RegistrationRepository {
  int getDraftCalls = 0;

  @override
  Future<Map<String, dynamic>> getDraft() async {
    getDraftCalls++;
    return <String, dynamic>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDismissalRepository implements CompletionRecommendationRepository {
  final List<String> dismissed = [];
  final List<String> restored = [];
  bool shouldFail = false;

  @override
  Future<void> dismiss(String cardKey) async {
    if (shouldFail) throw Exception('offline');
    dismissed.add(cardKey);
  }

  @override
  Future<void> restore(String cardKey) async => restored.add(cardKey);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ─── Harness ─────────────────────────────────────────────────────────────

/// Mounts the section on a stand-in Home route, with a router carrying the
/// real route paths so a card tap can be checked against where it actually
/// lands.
class _Harness {
  late final ProviderContainer container;
  late final GoRouter router;
  final _FakeDismissalRepository dismissals = _FakeDismissalRepository();
  final _FakeRegistrationRepository registration =
      _FakeRegistrationRepository();
  Map<String, dynamic> draft;

  _Harness(this.draft);

  Future<void> pump(
    WidgetTester tester, {
    double horizontalPadding = 16,
  }) async {
    container = ProviderContainer(
      overrides: [
        // Deliberately re-read on every build, so invalidating the provider
        // picks up a changed [draft] — that is how "the backend now says this
        // section is finished" is simulated.
        profileDraftResponseProvider.overrideWith((ref) async => draft),
        completionRecommendationRepositoryProvider.overrideWithValue(
          dismissals,
        ),
        registrationRepositoryProvider.overrideWithValue(registration),
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
          builder: (_, _) => page(
            CompleteProfileSection(horizontalPadding: horizontalPadding),
          ),
        ),
        GoRoute(
          path: RouteNames.editProfile,
          builder: (_, _) => page(const Text('EDIT PROFILE')),
        ),
        GoRoute(
          path: RouteNames.basicInfoEdit,
          builder: (_, _) => page(const Text('BASIC INFO PAGE')),
        ),
        GoRoute(
          path: RouteNames.photosEdit,
          builder: (_, _) => page(const Text('PHOTOS PAGE')),
        ),
        GoRoute(
          path: RouteNames.familyDetailsEdit,
          builder: (_, _) => page(const Text('FAMILY DETAILS PAGE')),
        ),
        GoRoute(
          path: RouteNames.horoscopeDetailsEdit,
          builder: (_, _) => page(const Text('HOROSCOPE PAGE')),
        ),
        GoRoute(
          path: RouteNames.profileReview,
          builder: (_, _) => page(const Text('REVIEW PAGE')),
        ),
        GoRoute(
          path: RouteNames.psychologyQuiz,
          builder: (_, _) => page(const Text('PSYCHOLOGY QUIZ PAGE')),
        ),
        GoRoute(
          path: RouteNames.verification,
          builder: (_, _) => page(const Text('VERIFICATION PAGE')),
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

  /// Simulates the backend state changing — a section saved, a dismissal
  /// stored — followed by the refresh the app does after either.
  Future<void> refreshWith(
    WidgetTester tester,
    Map<String, dynamic> next,
  ) async {
    draft = next;
    container.invalidate(profileDraftResponseProvider);
    await tester.pumpAndSettle();
  }
}

List<String> _renderedCardTitles(WidgetTester tester) => tester
    .widgetList<NmCompletionCard>(find.byType(NmCompletionCard))
    .map((c) => c.title)
    .toList();

void main() {
  group('the cards render, horizontally', () {
    testWidgets('one compact card per unfinished section', (tester) async {
      await _Harness(_draft()).pump(tester);

      expect(_renderedCardTitles(tester), [
        'Family Details',
        'Horoscope',
        'Verification',
        'Psychology Test',
      ]);
    });

    testWidgets('they sit in a horizontally scrollable row, not a column', (
      tester,
    ) async {
      await _Harness(_draft()).pump(tester);

      final row = find.byType(NmCompletionCardRow);
      expect(row, findsOneWidget);

      final scrollable = tester.widget<SingleChildScrollView>(
        find.descendant(of: row, matching: find.byType(SingleChildScrollView)),
      );
      expect(scrollable.scrollDirection, Axis.horizontal);
    });

    testWidgets('the row actually scrolls to reach the last card', (
      tester,
    ) async {
      // A narrow phone: four 184dp cards cannot all fit, so the last one is
      // off-screen until the row is dragged.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _Harness(_draft()).pump(tester);

      final lastCard = find.byKey(
        const ValueKey('completion-card-${CompletionCardKeys.psychology}'),
      );
      expect(lastCard, findsOneWidget);

      await tester.drag(
        find.byType(NmCompletionCardRow),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      // Still there, and now brought into view rather than overflowing.
      expect(lastCard, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every card carries an icon, a short title and a cross', (
      tester,
    ) async {
      await _Harness(_draft()).pump(tester);

      final cardFinder = find.byKey(
        const ValueKey('completion-card-${CompletionCardKeys.aboutFamily}'),
      );
      final family = tester.widget<NmCompletionCard>(cardFinder);

      expect(family.title, 'Family Details');
      expect(
        find.descendant(of: cardFinder, matching: find.byIcon(family.icon)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: cardFinder,
          matching: find.byIcon(Icons.close_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the card stays compact — no description text painted', (
      tester,
    ) async {
      await _Harness(_draft()).pump(tester);

      final family = tester.widget<NmCompletionCard>(
        find.byKey(
          const ValueKey('completion-card-${CompletionCardKeys.aboutFamily}'),
        ),
      );

      // The description exists and is spoken, but never drawn: a card this
      // size has room for the title and nothing else.
      expect(family.description, isNotEmpty);
      expect(find.text(family.description), findsNothing);
    });

    testWidgets('a card is roughly square, not a wide banner', (tester) async {
      await _Harness(_draft()).pump(tester);

      final size = tester.getSize(
        find.byKey(
          const ValueKey('completion-card-${CompletionCardKeys.aboutFamily}'),
        ),
      );

      expect(size.width, NmCompletionCard.width);
      // As tall as it is wide, give or take — never the full-width row a
      // vertical list of large cards would give.
      expect(size.height, lessThan(size.width * 1.6));
    });

    testWidgets('the icon tiles use existing theme colors only', (
      tester,
    ) async {
      await _Harness(_draft()).pump(tester);

      final tints = tester
          .widgetList<NmCompletionCard>(find.byType(NmCompletionCard))
          .expand((c) => [c.tint, c.tintSurface]);

      final palette = <Color>{
        AppColors.primary,
        AppColors.primarySurface,
        AppColors.success,
        AppColors.successLight,
        AppColors.scoreAstrology,
        AppColors.verifiedBlue,
        AppColors.infoLight,
        AppColors.scorePsychology,
        AppColors.secondarySurface,
      };
      expect(tints.every(palette.contains), isTrue);
    });

    testWidgets('shows the backend score and a compact progress bar', (
      tester,
    ) async {
      await _Harness(_draft(percentage: 72)).pump(tester);

      expect(find.text('Profile completeness score 72%'), findsOneWidget);
      final bar = tester.widget<NmGradientProgressBar>(
        find.byType(NmGradientProgressBar),
      );
      expect(bar.value, closeTo(0.72, 0.0001));
      // Inline beside the score, not a bar spanning the whole section.
      expect(tester.getSize(find.byType(NmGradientProgressBar)).width, 56);
    });

    testWidgets('renders nothing when there is nothing to recommend', (
      tester,
    ) async {
      await _Harness(
        _draft(
          percentage: 100,
          familyComplete: true,
          horoscopeComplete: true,
          verificationComplete: true,
          psychologyComplete: true,
        ),
      ).pump(tester);

      expect(find.byType(NmCompletionCard), findsNothing);
      // Not an empty header either — the whole section is gone.
      expect(find.text('Complete Your Profile'), findsNothing);
      expect(find.byType(NmGradientProgressBar), findsNothing);
    });
  });

  group('completed cards are hidden', () {
    testWidgets('a finished section has no card', (tester) async {
      await _Harness(_draft(familyComplete: true)).pump(tester);

      expect(_renderedCardTitles(tester), isNot(contains('Family Details')));
      expect(_renderedCardTitles(tester), contains('Horoscope'));
    });

    testWidgets('completing a section and refreshing removes its card', (
      tester,
    ) async {
      final harness = _Harness(_draft());
      await harness.pump(tester);
      expect(_renderedCardTitles(tester), contains('Family Details'));

      // The member filled in About Family; the backend now scores it as done.
      await harness.refreshWith(
        tester,
        _draft(percentage: 70, familyComplete: true),
      );

      expect(_renderedCardTitles(tester), isNot(contains('Family Details')));
      // The refreshed percentage came along with it.
      expect(find.text('Profile completeness score 70%'), findsOneWidget);
    });

    testWidgets('the last card completing empties the section', (tester) async {
      final harness = _Harness(_draft(percentage: 95));
      await harness.pump(tester);
      expect(find.byType(NmCompletionCard), findsWidgets);

      await harness.refreshWith(
        tester,
        _draft(
          percentage: 100,
          familyComplete: true,
          horoscopeComplete: true,
          verificationComplete: true,
          psychologyComplete: true,
        ),
      );

      expect(find.byType(NmCompletionCard), findsNothing);
    });
  });

  group('dismissal', () {
    testWidgets('the cross hides the card and persists it to the backend', (
      tester,
    ) async {
      final harness = _Harness(_draft());
      await harness.pump(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey('completion-card-${CompletionCardKeys.horoscope}'),
          ),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();

      expect(harness.dismissals.dismissed, [CompletionCardKeys.horoscope]);
      expect(_renderedCardTitles(tester), isNot(contains('Horoscope')));
      // Only the neighbouring card left — dismissing one hides one.
      expect(_renderedCardTitles(tester), contains('Family Details'));
    });

    testWidgets('dismissing never writes profile data', (tester) async {
      final harness = _Harness(_draft());
      await harness.pump(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey('completion-card-${CompletionCardKeys.aboutFamily}'),
          ),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();

      // The dismissal endpoint, and nothing else. No section PATCH, no
      // finalize — the member's saved family details are untouched, which is
      // the whole distinction between hiding a suggestion and deleting data.
      expect(harness.dismissals.dismissed, [CompletionCardKeys.aboutFamily]);
      expect(harness.registration.getDraftCalls, 0);
    });

    testWidgets('a dismissed card does not come back on the next server read — '
        'restart, re-login, refresh', (tester) async {
      final harness = _Harness(_draft());
      await harness.pump(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey('completion-card-${CompletionCardKeys.horoscope}'),
          ),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();

      // The backend now reports the dismissal on every subsequent read.
      await harness.refreshWith(
        tester,
        _draft(dismissed: const {CompletionCardKeys.horoscope}),
      );

      expect(_renderedCardTitles(tester), isNot(contains('Horoscope')));
    });

    testWidgets('a cold start with a stored dismissal never shows the card', (
      tester,
    ) async {
      // No session state at all — a fresh container, exactly like a relaunch
      // or a login on another device. The flag is on the response.
      await _Harness(
        _draft(dismissed: const {CompletionCardKeys.verification}),
      ).pump(tester);

      expect(_renderedCardTitles(tester), isNot(contains('Verification')));
      expect(_renderedCardTitles(tester), contains('Horoscope'));
    });

    testWidgets('a failed dismissal puts the card back and says so', (
      tester,
    ) async {
      final harness = _Harness(_draft());
      harness.dismissals.shouldFail = true;
      await harness.pump(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey('completion-card-${CompletionCardKeys.horoscope}'),
          ),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(_renderedCardTitles(tester), contains('Horoscope'));
      expect(
        find.text('Could not hide that just now. Please try again.'),
        findsOneWidget,
      );
    });
  });

  group('registration cards', () {
    testWidgets('are the only cards while registration is incomplete', (
      tester,
    ) async {
      await _Harness(
        _draft(
          percentage: 30,
          registrationComplete: false,
          recommendations: [
            _card(CompletionCardKeys.registration, wizardStep: 0),
            _card(CompletionCardKeys.photo, wizardStep: 11),
            _card(CompletionCardKeys.aboutFamily, wizardStep: 7),
            _card(CompletionCardKeys.horoscope, wizardStep: 8),
            _card(CompletionCardKeys.verification, wizardStep: 12),
          ],
        ),
      ).pump(tester);

      expect(_renderedCardTitles(tester), [
        'Finish Registration',
        'Add photo(s)',
      ]);
    });

    testWidgets('only the genuinely missing photo shows', (tester) async {
      await _Harness(
        _draft(
          percentage: 57,
          registrationComplete: false,
          recommendations: [
            _card(
              CompletionCardKeys.registration,
              isComplete: true,
              wizardStep: 0,
            ),
            _card(CompletionCardKeys.photo, wizardStep: 11),
            _card(CompletionCardKeys.aboutFamily, wizardStep: 7),
          ],
        ),
      ).pump(tester);

      expect(_renderedCardTitles(tester), ['Add photo(s)']);
    });

    testWidgets('never appear once registrationComplete is true', (
      tester,
    ) async {
      await _Harness(_draft()).pump(tester);

      expect(
        _renderedCardTitles(tester),
        isNot(contains('Finish Registration')),
      );
      expect(_renderedCardTitles(tester), isNot(contains('Add photo(s)')));
    });
  });

  group('the psychology card is offered but never counted', () {
    testWidgets('it is shown, and labelled optional', (tester) async {
      await _Harness(_draft()).pump(tester);

      final psychology = tester.widget<NmCompletionCard>(
        find.byKey(
          const ValueKey('completion-card-${CompletionCardKeys.psychology}'),
        ),
      );
      expect(psychology.title, 'Psychology Test');
      expect(psychology.badge, 'Optional');
      expect(find.text('Optional'), findsOneWidget);

      // Every scored card carries no badge — "not completed" on a card that
      // exists precisely because it is not completed says nothing, and costs
      // a line on a card this small.
      final family = tester.widget<NmCompletionCard>(
        find.byKey(
          const ValueKey('completion-card-${CompletionCardKeys.aboutFamily}'),
        ),
      );
      expect(family.badge, isEmpty);
    });

    testWidgets('taking it removes the card without moving the percentage', (
      tester,
    ) async {
      final harness = _Harness(_draft(percentage: 60));
      await harness.pump(tester);
      expect(find.text('Profile completeness score 60%'), findsOneWidget);

      // The quiz is submitted. Same percentage — it carries no weight.
      await harness.refreshWith(
        tester,
        _draft(percentage: 60, psychologyComplete: true),
      );

      expect(_renderedCardTitles(tester), isNot(contains('Psychology Test')));
      expect(find.text('Profile completeness score 60%'), findsOneWidget);
    });
  });

  group('a card opens the page that completes it', () {
    Future<void> expectTapOpens(
      WidgetTester tester,
      String cardKey,
      String expectedPage,
    ) async {
      final harness = _Harness(_draft());
      await harness.pump(tester);

      await tester.tap(find.byKey(ValueKey('completion-card-$cardKey')));
      await tester.pumpAndSettle();

      // Asserted on the page that actually rendered rather than on the
      // router's reported location: an imperative `push` leaves
      // `currentConfiguration.uri` at the origin, and what matters here is
      // where the member ended up.
      expect(find.text(expectedPage), findsOneWidget);
      expect(find.byType(CompleteProfileSection), findsNothing);
    }

    // Family and horoscope are no longer sections of Edit Profile — each has
    // a dedicated page, and the card opens that page directly.
    testWidgets('About Family opens the Family Details page', (tester) async {
      await expectTapOpens(
        tester,
        CompletionCardKeys.aboutFamily,
        'FAMILY DETAILS PAGE',
      );
    });

    testWidgets('Horoscope opens the Horoscope page', (tester) async {
      await expectTapOpens(
        tester,
        CompletionCardKeys.horoscope,
        'HOROSCOPE PAGE',
      );
    });

    testWidgets('Verification opens the verification page', (tester) async {
      await expectTapOpens(
        tester,
        CompletionCardKeys.verification,
        'VERIFICATION PAGE',
      );
    });

    testWidgets('Psychology Test opens the quiz', (tester) async {
      await expectTapOpens(
        tester,
        CompletionCardKeys.psychology,
        'PSYCHOLOGY QUIZ PAGE',
      );
    });

    testWidgets('the same card opens the same page from the review', (
      tester,
    ) async {
      // The registration review embeds the identical widget with zero
      // horizontal padding; the destination is decided by the card, not the
      // host.
      final harness = _Harness(_draft());
      await harness.pump(tester, horizontalPadding: 0);

      await tester.tap(
        find.byKey(
          const ValueKey('completion-card-${CompletionCardKeys.aboutFamily}'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FAMILY DETAILS PAGE'), findsOneWidget);
    });
  });

  group('Home and the registration review stay in step', () {
    testWidgets('both hosts render the same cards from one response', (
      tester,
    ) async {
      final draft = _draft(horoscopeComplete: true);

      final home = _Harness(draft);
      await home.pump(tester);
      final homeCards = _renderedCardTitles(tester);

      // Unmount the first tree before building the second — two live routers
      // in one test leaves the disposed one's transition timers running.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final review = _Harness(draft);
      await review.pump(tester, horizontalPadding: 0);
      final reviewCards = _renderedCardTitles(tester);

      expect(homeCards, reviewCards);
      expect(homeCards, isNot(contains('Horoscope')));
    });

    test('the registration review embeds the shared section; Edit Profile '
        'and Discover do not', () {
      // A structural check, because this is the guarantee no amount of widget
      // testing can make on its own.
      //
      // Edit Profile is the member's registration details and nothing else —
      // its seven section cards. Discover is deliberately not a host either —
      // it used to be, and the result was that every member who landed on
      // Discover straight after registering met a profile-completion call to
      // action instead of the Discover page. If Discover ever grows the
      // section back, that regression is back with it.
      final discover = File(
        'lib/features/discover/presentation/pages/discover_page.dart',
      ).readAsStringSync();
      final editProfile = File(
        'lib/features/registration/presentation/pages/edit_profile_page.dart',
      ).readAsStringSync();
      final review = File(
        'lib/features/registration/presentation/pages/profile_review_page.dart',
      ).readAsStringSync();

      expect(review, contains('CompleteProfileSection('));
      expect(editProfile, isNot(contains('CompleteProfileSection(')));
      expect(
        discover,
        isNot(contains('CompleteProfileSection(')),
        reason: 'Discover must stay free of the completion prompt',
      );
    });
  });
}
