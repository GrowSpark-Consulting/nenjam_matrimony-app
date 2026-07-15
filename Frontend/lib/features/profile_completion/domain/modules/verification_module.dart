import '../profile_completion_module.dart';

/// Proportional over 3 *actionable* verification flags — mobile is excluded
/// since it's auto-verified at signup/login and never user-actionable here.
class VerificationModule extends ProfileCompletionModule {
  const VerificationModule();

  @override
  String get id => 'verification';

  @override
  double get weight => 10;

  @override
  ModuleStatus evaluate(ProfileCompletionContext context) {
    final v = context.draft.verificationStatus;
    final flags = [
      v.emailVerified,
      v.faceVerified,
      v.aadhaarVerified || v.govIdVerified,
    ];
    final done = flags.where((f) => f).length;
    final progress = done / flags.length;
    return ModuleStatus(
      isComplete: progress >= 1.0,
      progress: progress,
      wizardStep: 12,
    );
  }
}
