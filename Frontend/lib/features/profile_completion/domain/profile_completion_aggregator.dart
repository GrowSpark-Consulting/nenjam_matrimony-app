import 'completion_recommendation.dart';
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

  /// Whether every counted registration item — the 20 fields and a photo — is
  /// answered. When true the screen hides the Registration information group
  /// entirely: a member who just finished signing up must not be asked again
  /// for what they have already given.
  final bool registrationComplete;

  /// Every registration item with its answered state, in screen order.
  /// Populated whether or not the group is shown, so the drawer and the
  /// dashboard can deep-link without a second request.
  final List<RequiredFieldStatus> requiredFields;

  /// The "Complete Your Profile" cards the backend reports, in display order
  /// and unfiltered — [visibleRecommendations] is what decides which of them
  /// a screen draws. Empty on a response that predates them, which simply
  /// means no section is rendered.
  final List<CompletionRecommendation> recommendations;

  const ProfileCompleteness({
    required this.percentage,
    required this.tier,
    required this.completedModules,
    required this.missingModules,
    required this.highestImpactModule,
    this.registrationComplete = true,
    this.requiredFields = const [],
    this.recommendations = const [],
  });

  /// The registration answers still missing, in screen order. Empty when the
  /// group is complete, and never includes the optional sub-community.
  List<RequiredFieldStatus> get missingRequiredFields => requiredFields
      .where((f) => !f.isComplete && !f.optional)
      .toList(growable: false);

  /// The cards to draw right now — finished, dismissed and out-of-phase ones
  /// already removed. Both Home and Edit Profile read this, which is what
  /// makes them show the same thing.
  List<CompletionRecommendation> visibleCards({
    Set<String> pendingDismissals = const {},
  }) => visibleRecommendations(
        recommendations,
        registrationComplete: registrationComplete,
        pendingDismissals: pendingDismissals,
      );
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
  List<Map<String, dynamic>> breakdownJson, {
  List<Map<String, dynamic>> requiredFieldsJson = const [],
  List<Map<String, dynamic>> recommendationsJson = const [],
  bool? registrationComplete,
}) {
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

  final requiredFields = requiredFieldsJson
      .map(RequiredFieldStatus.fromJson)
      .toList(growable: false);

  return ProfileCompleteness(
    percentage: percentage,
    tier: _tierFor(percentage),
    completedModules: completed,
    missingModules: missing,
    highestImpactModule: missing.isNotEmpty ? missing.first : null,
    // A response that predates `registrationComplete` — an older server, a
    // cached body — must not make the screen nag for fields it knows nothing
    // about, so absence is read as "nothing to ask for" and the group stays
    // hidden. Deriving it from requiredFields when they ARE present keeps the
    // two consistent even if a server ever sends one without the other.
    registrationComplete: registrationComplete ??
        (requiredFields.isEmpty ||
            requiredFields.every((f) => f.isComplete || f.optional)),
    requiredFields: requiredFields,
    recommendations: recommendationsJson
        .map(CompletionRecommendation.fromJson)
        .toList(growable: false),
  );
}
