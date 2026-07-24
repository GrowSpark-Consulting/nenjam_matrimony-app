import 'profile_completion_module.dart';

enum ProfileStrengthTier { building, good, strong, exceptional }

/// One evaluated module paired with its status, for display.
class EvaluatedModule {
  final ModuleBreakdown module;
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

/// Shapes the backend's authoritative completion percentage + per-module
/// breakdown (`GET /profiles/draft`'s `completionPercentage` /
/// `completionBreakdown` — see ProfileDraftService/ProfileCompletionService
/// on the backend) into the display-ready [ProfileCompleteness] the Profile
/// Completion screen and Profile dashboard already render.
///
/// No weight, no completion rule, and no percentage is computed here — this
/// function only sorts/splits the modules the backend already scored, so
/// there is exactly one place (the backend) that can ever disagree with
/// itself about how complete a profile is.
ProfileCompleteness profileCompletenessFromBackend(
  int percentage,
  List<Map<String, dynamic>> breakdownJson,
) {
  final evaluated = breakdownJson.map((json) {
    final module = ModuleBreakdown(
      id: json['id'] as String,
      weight: (json['weight'] as num).toDouble(),
    );
    final status = ModuleStatus(
      isComplete: json['isComplete'] as bool,
      wizardStep: (json['wizardStep'] as num?)?.toInt(),
    );
    return EvaluatedModule(module, status);
  }).toList();

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
