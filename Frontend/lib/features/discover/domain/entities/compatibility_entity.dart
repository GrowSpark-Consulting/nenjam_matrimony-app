/// AI / astrology / psychology match scores for a discovery profile,
/// kept separate from [DiscoveryProfileEntity] so scoring can evolve
/// (new algorithms, weighting) without reshaping the profile itself.
class CompatibilityEntity {
  final int aiMatchPercent;
  final int astroMatchPercent;
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
