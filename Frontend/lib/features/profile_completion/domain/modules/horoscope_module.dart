import '../profile_completion_module.dart';

/// Done when horoscope is marked available, or any core horoscope field has
/// been filled in. Explicitly optional in the wizard's own copy — kept as
/// the lowest-weighted module for that reason (see plan doc).
class HoroscopeModule extends ProfileCompletionModule {
  const HoroscopeModule();

  @override
  String get id => 'horoscope';

  @override
  double get weight => 5;

  @override
  ModuleStatus evaluate(ProfileCompletionContext context) {
    final h = context.draft.horoscopeDetails;
    final hasAny = h.horoscopeAvailable ||
        h.birthPlace.isNotEmpty ||
        h.rashi.isNotEmpty ||
        h.nakshatra.isNotEmpty ||
        h.star.isNotEmpty;
    return ModuleStatus(
      isComplete: hasAny,
      progress: hasAny ? 1.0 : 0.0,
      wizardStep: 8,
    );
  }
}
