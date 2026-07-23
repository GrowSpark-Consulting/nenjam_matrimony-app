import '../profile_completion_module.dart';

/// Step 13 (Verification) — worth 25 of the overall 100 points, 5 per
/// verified flag: mobile, income, asset, aadhaar/government ID, NRI. Email
/// is deliberately excluded — it stays part of account verification/security
/// (see AuthUser.emailVerified) but must never add to this module's score,
/// per the product requirement that Step 13 tops out at exactly 25%.
/// [weight] was raised from 10 to 25 to match; [RegistrationModule.weight]
/// was reduced 50 -> 35 to keep all modules' weights summing to 100 (see its
/// own doc comment).
class VerificationModule extends ProfileCompletionModule {
  const VerificationModule();

  @override
  String get id => 'verification';

  @override
  double get weight => 25;

  @override
  ModuleStatus evaluate(ProfileCompletionContext context) {
    final v = context.draft.verificationStatus;
    final flags = [
      v.mobileVerified,
      v.incomeVerified,
      v.assetVerified,
      v.aadhaarVerified || v.govIdVerified,
      v.nriVerified,
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
