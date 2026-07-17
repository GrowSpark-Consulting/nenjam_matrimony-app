/// Read-only family background for another member's profile detail.
///
/// Field names mirror `features/registration`'s `FamilyDetails` draft model
/// (`step_family.dart`) so mock/real data can be mapped 1:1 later.
class FamilyInfoEntity {
  final String fatherName;
  final String fatherOccupation;
  final String motherName;
  final String motherOccupation;
  final String familyType;
  final String familyValues;
  final String familyStatus;
  final int brothers;
  final int sisters;

  const FamilyInfoEntity({
    this.fatherName = '',
    this.fatherOccupation = '',
    this.motherName = '',
    this.motherOccupation = '',
    this.familyType = '',
    this.familyValues = '',
    this.familyStatus = '',
    this.brothers = 0,
    this.sisters = 0,
  });
}
