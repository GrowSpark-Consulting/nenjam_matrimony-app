import '../profile_completion_module.dart';

/// Done when at least one partner-preference field has been filled in.
class PartnerPreferenceModule extends ProfileCompletionModule {
  const PartnerPreferenceModule();

  @override
  String get id => 'partnerPreference';

  @override
  double get weight => 15;

  @override
  ModuleStatus evaluate(ProfileCompletionContext context) {
    final pref = context.draft.partnerPreference;
    final hasAny = pref.preferredAgeRange.isNotEmpty ||
        pref.preferredHeightRange.isNotEmpty ||
        pref.religionPref.isNotEmpty ||
        pref.castePref.isNotEmpty ||
        pref.educationPref.isNotEmpty ||
        pref.locationPref.isNotEmpty;
    return ModuleStatus(
      isComplete: hasAny,
      progress: hasAny ? 1.0 : 0.0,
      wizardStep: 10,
    );
  }
}
