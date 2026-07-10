/// Self-summary of the signed-in user's horoscope details, plus their
/// matching opt-in status.
class HoroscopeSummary {
  final String? rasi;
  final String? nakshatra;
  final String? dosham;
  final String? birthTime;
  final String? birthPlace;
  final bool matchingEnabled;

  const HoroscopeSummary({
    this.rasi,
    this.nakshatra,
    this.dosham,
    this.birthTime,
    this.birthPlace,
    this.matchingEnabled = true,
  });

  HoroscopeSummary copyWith({bool? matchingEnabled}) => HoroscopeSummary(
        rasi: rasi,
        nakshatra: nakshatra,
        dosham: dosham,
        birthTime: birthTime,
        birthPlace: birthPlace,
        matchingEnabled: matchingEnabled ?? this.matchingEnabled,
      );
}

/// One component of a 2-person compatibility breakdown (e.g. "Nakshatra
/// Match").
class CompatibilityFactor {
  final String label;
  final int score;
  final int maxScore;

  const CompatibilityFactor({
    required this.label,
    required this.score,
    required this.maxScore,
  });
}

/// A 2-person horoscope + personality compatibility result.
class CompatibilityResult {
  final int score;
  final String matchLabel;
  final List<CompatibilityFactor> factors;

  const CompatibilityResult({
    required this.score,
    required this.matchLabel,
    this.factors = const [],
  });
}
