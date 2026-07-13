import 'modules/horoscope_module.dart';
import 'modules/partner_preference_module.dart';
import 'modules/photos_module.dart';
import 'modules/registration_module.dart';
import 'modules/verification_module.dart';
import 'profile_completion_module.dart';

/// The active module registry. Adding a module means adding one class + one
/// entry here — the aggregator below never needs to change.
const List<ProfileCompletionModule> profileCompletionModules = [
  RegistrationModule(),
  PhotosModule(),
  PartnerPreferenceModule(),
  HoroscopeModule(),
  VerificationModule(),
];

enum ProfileStrengthTier { building, good, strong, exceptional }

/// One evaluated module paired with its status, for display.
class EvaluatedModule {
  final ProfileCompletionModule module;
  final ModuleStatus status;

  const EvaluatedModule(this.module, this.status);
}

class ProfileCompleteness {
  final int percentage;
  final ProfileStrengthTier tier;
  final List<EvaluatedModule> completedModules;
  final List<EvaluatedModule> missingModules;

  /// Highest-weight incomplete module, or null if everything is complete.
  final EvaluatedModule? highestImpactModule;

  const ProfileCompleteness({
    required this.percentage,
    required this.tier,
    required this.completedModules,
    required this.missingModules,
    required this.highestImpactModule,
  });
}

ProfileStrengthTier _tierFor(int percentage) {
  if (percentage >= 90) return ProfileStrengthTier.exceptional;
  if (percentage >= 70) return ProfileStrengthTier.strong;
  if (percentage >= 40) return ProfileStrengthTier.good;
  return ProfileStrengthTier.building;
}

/// Evaluates every module in [profileCompletionModules] against [context]
/// and aggregates them into one overall score, matching the same formula
/// regardless of where the [ProfileCompletionContext] came from (a live
/// wizard session or a freshly-fetched snapshot).
ProfileCompleteness aggregateProfileCompletion(ProfileCompletionContext context) {
  final evaluated = profileCompletionModules
      .map((m) => EvaluatedModule(m, m.evaluate(context)))
      .toList();

  final totalWeight =
      profileCompletionModules.fold<double>(0, (sum, m) => sum + m.weight);
  final earnedWeight = evaluated.fold<double>(
    0,
    (sum, e) => sum + e.module.weight * e.status.progress,
  );
  final percentage =
      totalWeight == 0 ? 0 : ((earnedWeight / totalWeight) * 100).round();

  final completed = evaluated.where((e) => e.status.isComplete).toList();
  final missing = evaluated.where((e) => !e.status.isComplete).toList()
    ..sort((a, b) => b.module.weight.compareTo(a.module.weight));

  return ProfileCompleteness(
    percentage: percentage,
    tier: _tierFor(percentage),
    completedModules: completed,
    missingModules: missing,
    highestImpactModule: missing.isNotEmpty ? missing.first : null,
  );
}
