/// Read-only lifestyle & habits for another member's profile detail.
///
/// Field names mirror `features/registration`'s `LifestyleDetails` draft
/// model (`step_lifestyle.dart`). [physicalStatus] has no source anywhere
/// in registration yet — it's carried here for the UI's "Physical Status"
/// row but only ever mock-populated until a real field exists.
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
