/// AI / astrology / psychology match scores for a discovery profile,
/// kept separate from [DiscoveryProfileEntity] so scoring can evolve
/// (new algorithms, weighting) without reshaping the profile itself.
class CompatibilityEntity {
  final int aiMatchPercent;
  final int astroMatchPercent;

  /// Reserved and intentionally unpopulated: the backend sends `0` for every
  /// member — a psychology score would let one member infer another's quiz
  /// answers. Psychology never changes [aiMatchPercent] or
  /// [overallCompatibility] either. Parsed only for API compatibility; never
  /// render or branch on it (enforced by
  /// test/psychology_privacy_guard_test.dart).
  final int psychologyMatchPercent;
  final int overallCompatibility;

  // Additional axes for the Nenjam hub's multi-axis Compatibility Report.
  // Optional/defaulted so existing Discover/Matches call sites are unaffected.
  final int lifestyleMatchPercent;
  final int familyMatchPercent;
  final int educationMatchPercent;
  final int valuesMatchPercent;
  final int goalsMatchPercent;

  const CompatibilityEntity({
    this.aiMatchPercent = 0,
    this.astroMatchPercent = 0,
    this.psychologyMatchPercent = 0,
    this.overallCompatibility = 0,
    this.lifestyleMatchPercent = 0,
    this.familyMatchPercent = 0,
    this.educationMatchPercent = 0,
    this.valuesMatchPercent = 0,
    this.goalsMatchPercent = 0,
  });
}
