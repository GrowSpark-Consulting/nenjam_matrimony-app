/// The viewed member's horoscope facts, shown alongside a comparison score.
///
/// The comparison score itself is not duplicated here — it comes from
/// `DiscoveryProfileEntity.compatibility.astroMatchPercent`, which already
/// flows through the feed this profile was tapped from.
class HoroscopeInfoEntity {
  final String rasi;
  final String nakshatra;
  final String dosham;
  final bool matchingEnabled;
  final List<String> matchingPoints;

  const HoroscopeInfoEntity({
    this.rasi = '',
    this.nakshatra = '',
    this.dosham = '',
    this.matchingEnabled = true,
    this.matchingPoints = const [],
  });
}
