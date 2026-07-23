import '../profile_completion_module.dart';

/// Wraps [ProfileDraft.completionPercentage] directly — this module
/// deliberately has zero logic of its own, so the model's own formula stays
/// the single source of truth for "is the core registration data filled
/// in." If that getter's internal weighting ever changes, this module's
/// score changes with it automatically.
///
/// Weight reduced 50 -> 35 to make room for [VerificationModule] moving
/// 10 -> 25 (Step 13 must contribute exactly 25 of the overall 100 points)
/// while keeping every active module's weight summing to 100. This module
/// absorbs the full rebalance rather than spreading it across
/// PhotosModule/PartnerPreferenceModule/HoroscopeModule because its score is
/// already a smooth 0-100% proportion (many fields), so a weight change is
/// the least perceptible here — the other three are binary all-or-nothing
/// modules where users would otherwise notice their card's "worth" shrink.
class RegistrationModule extends ProfileCompletionModule {
  const RegistrationModule();

  @override
  String get id => 'registration';

  @override
  double get weight => 35;

  @override
  ModuleStatus evaluate(ProfileCompletionContext context) {
    final progress = context.draft.completionPercentage / 100;
    return ModuleStatus(
      isComplete: progress >= 1.0,
      progress: progress,
      // Jumps to whichever core step is least complete would require
      // per-step introspection the model doesn't expose; Basic Info (step 0)
      // is a reasonable, always-valid entry point into the core section.
      wizardStep: 0,
    );
  }
}
