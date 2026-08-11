import '../../domain/models/compatibility_result.dart';
import '../../domain/repositories/compatibility_repository.dart';
import '../../../../core/l10n/app_l10n.dart';

/// In-memory mock — no network calls. Default implementation until the
/// backend team ships real endpoints (see [ApiCompatibilityRepository]).
class MockCompatibilityRepository implements CompatibilityRepository {
  HoroscopeSummary _summary = const HoroscopeSummary(
    rasi: 'Simha',
    nakshatra: 'Magha',
    dosham: 'NONE',
    birthTime: '08:45 AM',
    birthPlace: 'Chennai, Tamil Nadu',
    matchingEnabled: true,
  );

  @override
  Future<HoroscopeSummary> getMyHoroscopeSummary() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _summary;
  }

  @override
  Future<void> setMatchingEnabled(bool enabled) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _summary = _summary.copyWith(matchingEnabled: enabled);
  }

  @override
  Future<CompatibilityResult> getCompatibility({String? targetUserId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final l10n = AppL10n.current;
    return CompatibilityResult(
      score: 85,
      matchLabel: l10n.astroExcellentMatch,
      factors: [
        CompatibilityFactor(label: l10n.astroNakshatraMatch, score: 36, maxScore: 40),
        CompatibilityFactor(label: l10n.astroRasiMatch, score: 24, maxScore: 30),
        CompatibilityFactor(label: l10n.astroDoshamMatch, score: 17, maxScore: 20),
        CompatibilityFactor(label: l10n.astroPersonalityMatch, score: 8, maxScore: 10),
      ],
    );
  }
}
