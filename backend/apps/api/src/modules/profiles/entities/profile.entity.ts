// Domain object the service layer works with, mapped from Prisma's
// UserProfile row by ProfileRepository — Prisma's generated type never
// leaks past the repository.
export class ProfileEntity {
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
