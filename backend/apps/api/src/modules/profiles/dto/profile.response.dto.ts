// Shape returned by GET /profiles/me and GET /profiles/:id.
// Field names match the Prisma UserProfile model (see schema.prisma), not
// the Flutter draft field names — this is the finalized, validated profile.
export class ProfileResponseDto {
  id!: string;
  userId!: string;
  firstName!: string;
  lastName!: string;
  dob!: Date;
  gender!: string;
  maritalStatus!: string;
  religion!: string;
  caste!: string;
  subCaste!: string | null;
  motherTongue!: string;
  heightCm!: number;
  weightKg!: number | null;
  annualIncomeLakhs!: string | null;
  highestEducation!: string;
  educationDetails!: string | null;
  profession!: string;
  employerName!: string | null;
  currentCity!: string;
  currentState!: string;
  nativeCity!: string | null;
  bio!: string | null;
  dietaryHabits!: string | null;
  smokingHabits!: string | null;
  drinkingHabits!: string | null;
  physicalStatus!: string | null;
  familyType!: string | null;
  familyStatus!: string | null;
  fatherOccupation!: string | null;
  motherOccupation!: string | null;
  siblings!: number | null;
  isProfileComplete!: boolean;
  profileCompletePct!: number;
}
