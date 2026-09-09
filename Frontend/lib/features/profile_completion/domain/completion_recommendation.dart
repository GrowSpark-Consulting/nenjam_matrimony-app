/// One "Complete Your Profile" recommendation card, exactly as the backend
/// reports it on `GET /profiles/draft`'s `recommendations` (see
/// `backend/apps/api/src/modules/profiles/domain/recommendation-cards.ts`).
///
/// A plain data holder, like [ModuleBreakdown] next door: the app never
/// decides whether a section is finished, only how to draw what the server
/// already decided. That is what lets Home and Edit Profile agree — they read
/// this same list out of the same response.
class CompletionRecommendation {
  /// Stable card id — one of [CompletionCardKeys].
  final String key;

  /// Whether the section behind the card is finished. Derived on the server
  /// from the very signal that scored the section, so it can never disagree
  /// with the percentage shown beside it.
  final bool isComplete;

  /// Whether the member has dismissed this card. Persisted server-side, so it
  /// survives a restart, a re-login and a reinstall — and it hides the
  /// suggestion only; the saved data behind the section is untouched.
  final bool isDismissed;

  /// False only for `psychology`, which is offered as optional and carries no
  /// weight until its scoring is approved.
  final bool affectsScore;

  /// Wizard step to open, in the same 0-indexed numbering
  /// `profileSectionRoute` already maps.
  final int wizardStep;

  const CompletionRecommendation({
    required this.key,
    required this.isComplete,
    required this.isDismissed,
    required this.affectsScore,
    required this.wizardStep,
  });

  /// Tolerant of a response that predates any of these fields: a missing flag
  /// reads as "not complete, not dismissed, counts toward the score" rather
  /// than throwing, so an older or newer server can never crash Home.
  factory CompletionRecommendation.fromJson(Map<String, dynamic> json) {
    return CompletionRecommendation(
      key: json['key'] as String? ?? '',
      isComplete: json['isComplete'] as bool? ?? false,
      isDismissed: json['isDismissed'] as bool? ?? false,
      affectsScore: json['affectsScore'] as bool? ?? true,
      wizardStep: (json['wizardStep'] as num?)?.toInt() ?? 0,
    );
  }

  CompletionRecommendation copyWith({bool? isDismissed}) =>
      CompletionRecommendation(
        key: key,
        isComplete: isComplete,
        isDismissed: isDismissed ?? this.isDismissed,
        affectsScore: affectsScore,
        wizardStep: wizardStep,
      );
}

/// The card ids, matching `RECOMMENDATION_CARD_KEYS` on the backend verbatim.
abstract final class CompletionCardKeys {
  static const String registration = 'registration';
  static const String photo = 'photo';
  static const String aboutFamily = 'about_family';
  static const String horoscope = 'horoscope';
  static const String verification = 'verification';
  static const String psychology = 'psychology';

  /// The two cards that stand in for an unfinished registration. They are
  /// shown *instead of* the section cards, never alongside them.
  static const Set<String> registrationGroup = {registration, photo};

  /// Every key this build knows how to draw. A card the server adds later is
  /// ignored rather than rendered blank.
  static const Set<String> known = {
    registration,
    photo,
    aboutFamily,
    horoscope,
    verification,
    psychology,
  };
}

/// The cards to actually put on screen, in server order.
///
/// The single place this decision is made, deliberately: Home and Edit
/// Profile both call it with the same [all] list, so the two screens cannot
/// show different cards for the same profile. The rules, in order:
///
///  * A finished card is gone. Nobody should be asked for what they've given.
///  * A dismissed card is gone — including [pendingDismissals], the ones this
///    session has just dismissed but whose refreshed response hasn't landed
///    yet, so the card leaves on tap rather than on the round trip.
///  * While registration is unfinished, ONLY the registration cards show. A
///    member who hasn't finished signing up is asked to finish signing up,
///    not to fill in their horoscope.
///  * Once it's finished, the registration cards never show again.
///  * An unrecognised key is dropped rather than drawn without copy.
List<CompletionRecommendation> visibleRecommendations(
  List<CompletionRecommendation> all, {
  required bool registrationComplete,
  Set<String> pendingDismissals = const {},
}) {
  return all
      .where((r) => CompletionCardKeys.known.contains(r.key))
      .where((r) => !r.isComplete)
      .where((r) => !r.isDismissed && !pendingDismissals.contains(r.key))
      .where(
        (r) =>
            CompletionCardKeys.registrationGroup.contains(r.key) ==
            !registrationComplete,
      )
      .toList(growable: false);
}
