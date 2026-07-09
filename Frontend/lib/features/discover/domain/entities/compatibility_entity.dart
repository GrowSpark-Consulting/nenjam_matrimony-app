/// AI / astrology / psychology match scores for a discovery profile,
/// kept separate from [DiscoveryProfileEntity] so scoring can evolve
/// (new algorithms, weighting) without reshaping the profile itself.
class CompatibilityEntity {
  final int aiMatchPercent;
  final int astroMatchPercent;
  final int psychologyMatchPercent;
  final int overallCompatibility;

  const CompatibilityEntity({
    this.aiMatchPercent = 0,
    this.astroMatchPercent = 0,
    this.psychologyMatchPercent = 0,
    this.overallCompatibility = 0,
  });
}
