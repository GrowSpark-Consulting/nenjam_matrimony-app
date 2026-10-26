/// Read-only lifestyle & habits for another member's profile detail.
///
/// Field names mirror `features/registration`'s `LifestyleDetails` draft
/// model (`step_lifestyle.dart`). [physicalStatus] comes from the profile
/// row's `physicalStatus` column; empty when the member never set it.
class LifestyleInfoEntity {
  final String eatingHabit;
  final String smoking;
  final String drinking;
  final String fitness;
  final String physicalStatus;
  final List<String> hobbies;
  final String aboutMe;

  const LifestyleInfoEntity({
    this.eatingHabit = '',
    this.smoking = '',
    this.drinking = '',
    this.fitness = '',
    this.physicalStatus = '',
    this.hobbies = const [],
    this.aboutMe = '',
  });
}
