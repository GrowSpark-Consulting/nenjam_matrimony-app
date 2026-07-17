/// The viewed member's stated partner preferences.
///
/// Field names mirror `features/registration`'s `PartnerPreference` draft
/// model (`step_partner_pref.dart`).
class PartnerPreferencesEntity {
  final String preferredAgeRange;
  final String preferredHeightRange;
  final String religionPref;
  final String castePref;
  final String educationPref;
  final String occupationPref;
  final String incomePref;
  final String locationPref;
  final String motherTonguePref;
  final String maritalStatusPref;

  const PartnerPreferencesEntity({
    this.preferredAgeRange = '',
    this.preferredHeightRange = '',
    this.religionPref = '',
    this.castePref = '',
    this.educationPref = '',
    this.occupationPref = '',
    this.incomePref = '',
    this.locationPref = '',
    this.motherTonguePref = '',
    this.maritalStatusPref = '',
  });
}
