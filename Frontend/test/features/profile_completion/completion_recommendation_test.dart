import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile_completion/domain/completion_recommendation.dart';
import 'package:nenjam_matrimony/features/profile_completion/domain/profile_completion_aggregator.dart';

/// Which "Complete Your Profile" cards are shown, and why.
///
/// [visibleRecommendations] is the only place that decision is made — Home
/// and Edit Profile both call it with the same server list, which is what
/// makes them agree. So these are the rules both screens obey, tested once.
void main() {
  Map<String, dynamic> cardJson(
    String key, {
    bool isComplete = false,
    bool isDismissed = false,
    bool affectsScore = true,
    int wizardStep = 0,
  }) => <String, dynamic>{
    'key': key,
    'isComplete': isComplete,
    'isDismissed': isDismissed,
    'affectsScore': affectsScore,
    'wizardStep': wizardStep,
  };

  CompletionRecommendation card(
    String key, {
    bool isComplete = false,
    bool isDismissed = false,
    bool affectsScore = true,
    int wizardStep = 0,
  }) => CompletionRecommendation.fromJson(
    cardJson(
      key,
      isComplete: isComplete,
      isDismissed: isDismissed,
      affectsScore: affectsScore,
      wizardStep: wizardStep,
    ),
  );

  /// The four section cards, none finished — a registered member with an
  /// otherwise empty profile.
  List<CompletionRecommendation> sectionCards({
    bool familyComplete = false,
    bool horoscopeComplete = false,
    bool verificationComplete = false,
    bool psychologyComplete = false,
    Set<String> dismissed = const {},
  }) => [
    card(
      CompletionCardKeys.registration,
      isComplete: true,
      wizardStep: 0,
    ),
    card(CompletionCardKeys.photo, isComplete: true, wizardStep: 11),
    card(
      CompletionCardKeys.aboutFamily,
      isComplete: familyComplete,
      isDismissed: dismissed.contains(CompletionCardKeys.aboutFamily),
      wizardStep: 7,
    ),
    card(
      CompletionCardKeys.horoscope,
      isComplete: horoscopeComplete,
      isDismissed: dismissed.contains(CompletionCardKeys.horoscope),
      wizardStep: 8,
    ),
    card(
      CompletionCardKeys.verification,
      isComplete: verificationComplete,
      isDismissed: dismissed.contains(CompletionCardKeys.verification),
      wizardStep: 12,
    ),
    card(
      CompletionCardKeys.psychology,
      isComplete: psychologyComplete,
      isDismissed: dismissed.contains(CompletionCardKeys.psychology),
      affectsScore: false,
      wizardStep: 9,
    ),
  ];

  List<String> keysOf(List<CompletionRecommendation> cards) =>
      cards.map((c) => c.key).toList();

  group('a card is shown while its section is unfinished', () {
    test('all four section cards show for a registered, empty profile', () {
      final visible = visibleRecommendations(
        sectionCards(),
        registrationComplete: true,
      );

      expect(keysOf(visible), [
        CompletionCardKeys.aboutFamily,
        CompletionCardKeys.horoscope,
        CompletionCardKeys.verification,
        CompletionCardKeys.psychology,
      ]);
    });

    test('server order is preserved', () {
      final visible = visibleRecommendations(
        sectionCards(),
        registrationComplete: true,
      );

      expect(visible.first.key, CompletionCardKeys.aboutFamily);
      expect(visible.last.key, CompletionCardKeys.psychology);
    });
  });

  group('completed cards are never shown', () {
    test('a finished section drops out', () {
      final visible = visibleRecommendations(
        sectionCards(familyComplete: true),
        registrationComplete: true,
      );

      expect(visible.map((c) => c.key), isNot(contains(CompletionCardKeys.aboutFamily)));
      expect(visible.map((c) => c.key), contains(CompletionCardKeys.horoscope));
    });

    test('a fully complete profile shows no cards at all', () {
      final visible = visibleRecommendations(
        sectionCards(
          familyComplete: true,
          horoscopeComplete: true,
          verificationComplete: true,
          psychologyComplete: true,
        ),
        registrationComplete: true,
      );

      expect(visible, isEmpty);
    });

    test('completing a section from either screen removes it for both', () {
      // The same server list, read by two screens: there is no per-screen
      // state to disagree about, so this is the same call twice.
      final fromHome = visibleRecommendations(
        sectionCards(horoscopeComplete: true),
        registrationComplete: true,
      );
      final fromEditProfile = visibleRecommendations(
        sectionCards(horoscopeComplete: true),
        registrationComplete: true,
      );

      expect(keysOf(fromHome), keysOf(fromEditProfile));
      expect(keysOf(fromHome), isNot(contains(CompletionCardKeys.horoscope)));
    });
  });

  group('dismissed cards stay hidden', () {
    test('a server-side dismissal hides the card', () {
      final visible = visibleRecommendations(
        sectionCards(dismissed: {CompletionCardKeys.horoscope}),
        registrationComplete: true,
      );

      expect(keysOf(visible), isNot(contains(CompletionCardKeys.horoscope)));
    });

    test(
      'it is still hidden on a fresh read of the same profile — a restart, '
      'a re-login, another device',
      () {
        // Nothing client-side carries over between those; the flag comes back
        // on the response, so a brand-new read hides it just the same.
        final afterRelogin = visibleRecommendations(
          sectionCards(dismissed: {CompletionCardKeys.horoscope}),
          registrationComplete: true,
          pendingDismissals: const {},
        );

        expect(keysOf(afterRelogin), isNot(contains(CompletionCardKeys.horoscope)));
      },
    );

    test('a dismissal this session hides the card before the refetch', () {
      final visible = visibleRecommendations(
        sectionCards(),
        registrationComplete: true,
        pendingDismissals: const {CompletionCardKeys.verification},
      );

      expect(keysOf(visible), isNot(contains(CompletionCardKeys.verification)));
      expect(keysOf(visible), contains(CompletionCardKeys.horoscope));
    });

    test('dismissing one card leaves the others alone', () {
      final visible = visibleRecommendations(
        sectionCards(dismissed: {CompletionCardKeys.aboutFamily}),
        registrationComplete: true,
      );

      expect(keysOf(visible), [
        CompletionCardKeys.horoscope,
        CompletionCardKeys.verification,
        CompletionCardKeys.psychology,
      ]);
    });
  });

  group('registration cards', () {
    test('appear only while registrationComplete is false', () {
      final incomplete = visibleRecommendations(
        [
          card(CompletionCardKeys.registration, wizardStep: 0),
          card(CompletionCardKeys.photo, wizardStep: 11),
          card(CompletionCardKeys.aboutFamily, wizardStep: 7),
          card(CompletionCardKeys.horoscope, wizardStep: 8),
        ],
        registrationComplete: false,
      );

      // Only what is genuinely missing from registration — and nothing else,
      // so a member who has not finished signing up is not also asked for a
      // horoscope.
      expect(keysOf(incomplete), [
        CompletionCardKeys.registration,
        CompletionCardKeys.photo,
      ]);
    });

    test('are gone once registration is complete', () {
      final visible = visibleRecommendations(
        sectionCards(),
        registrationComplete: true,
      );

      expect(keysOf(visible), isNot(contains(CompletionCardKeys.registration)));
      expect(keysOf(visible), isNot(contains(CompletionCardKeys.photo)));
    });

    test('only the genuinely missing one shows', () {
      // Every answer given, no photo uploaded.
      final visible = visibleRecommendations(
        [
          card(CompletionCardKeys.registration, isComplete: true),
          card(CompletionCardKeys.photo, wizardStep: 11),
        ],
        registrationComplete: false,
      );

      expect(keysOf(visible), [CompletionCardKeys.photo]);
    });
  });

  group('the psychology card is optional', () {
    test('it is flagged as not affecting the score', () {
      final psychology = sectionCards().firstWhere(
        (c) => c.key == CompletionCardKeys.psychology,
      );

      expect(psychology.affectsScore, isFalse);
    });

    test('every other card does affect the score', () {
      final others = sectionCards().where(
        (c) => c.key != CompletionCardKeys.psychology,
      );

      expect(others.every((c) => c.affectsScore), isTrue);
    });

    test('it has no module in the breakdown, so it cannot move the figure', () {
      // The percentage is the backend's, carried through untouched, and the
      // four scored slices still sum to 100 with no psychology term.
      final completeness = profileCompletenessFromBackend(
        70,
        [
          {'id': 'registration', 'weight': 60, 'isComplete': true, 'wizardStep': 0},
          {'id': 'family', 'weight': 10, 'isComplete': true, 'wizardStep': 7},
          {'id': 'horoscope', 'weight': 5, 'isComplete': false, 'wizardStep': 8},
          {'id': 'verification', 'weight': 25, 'isComplete': false, 'wizardStep': 12},
        ],
        recommendationsJson: [
          cardJson(CompletionCardKeys.psychology, affectsScore: false, wizardStep: 9),
        ],
      );

      expect(completeness.percentage, 70);
      final ids = [
        ...completeness.completedModules.map((m) => m.module.id),
        ...completeness.missingModules.map((m) => m.module.id),
      ];
      expect(ids, isNot(contains('psychology')));
      expect(
        [...completeness.completedModules, ...completeness.missingModules]
            .fold<double>(0, (sum, m) => sum + m.module.weight),
        100,
      );
      // And the card is offered regardless.
      expect(
        completeness.visibleCards().map((c) => c.key),
        contains(CompletionCardKeys.psychology),
      );
    });
  });

  group('parsing', () {
    test('reads the backend shape off the draft response', () {
      final completeness = profileCompletenessFromBackend(
        45,
        const [],
        registrationComplete: true,
        recommendationsJson: [
          cardJson(CompletionCardKeys.aboutFamily, wizardStep: 7),
          cardJson(CompletionCardKeys.horoscope, isDismissed: true, wizardStep: 8),
        ],
      );

      expect(completeness.recommendations.length, 2);
      expect(completeness.recommendations.first.wizardStep, 7);
      expect(completeness.recommendations.last.isDismissed, isTrue);
      expect(keysOf(completeness.visibleCards()), [CompletionCardKeys.aboutFamily]);
    });

    test('a response with no recommendations renders no section', () {
      final completeness = profileCompletenessFromBackend(45, const []);

      expect(completeness.recommendations, isEmpty);
      expect(completeness.visibleCards(), isEmpty);
    });

    test('a card key this build does not know is dropped, not drawn blank', () {
      final visible = visibleRecommendations([
        card('a_card_from_a_newer_server', wizardStep: 3),
        card(CompletionCardKeys.horoscope, wizardStep: 8),
      ], registrationComplete: true);

      expect(keysOf(visible), [CompletionCardKeys.horoscope]);
    });

    test('missing flags default to shown-and-counted rather than throwing', () {
      final parsed = CompletionRecommendation.fromJson(const {
        'key': CompletionCardKeys.horoscope,
      });

      expect(parsed.isComplete, isFalse);
      expect(parsed.isDismissed, isFalse);
      expect(parsed.affectsScore, isTrue);
      expect(parsed.wizardStep, 0);
    });
  });
}
