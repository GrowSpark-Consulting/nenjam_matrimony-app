import { PhotoEntity } from './photo.entity';
import { PartnerPreferenceEntity } from './partner-preference.entity';
import { AstrologyProfileEntity } from './astrology-profile.entity';
import { ProfileCompletionEntity } from './profile-completion.entity';

// Domain object the service layer works with, mapped from Prisma's
// UserProfile row by ProfileRepository — Prisma's generated type never
// leaks past the repository. The nested fields (photos/partnerPreference/
// astrology/completion) are assembled by ProfileService.getOwn() from the
// other repositories in this module — they aren't UserProfile columns.
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
  community!: string | null;
  denomination!: string | null;
  motherTongue!: string;
  languagesKnown!: string[];
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
  country!: string | null;
  area!: string | null;
  pinCode!: string | null;
  bio!: string | null;
  dietaryHabits!: string | null;
  smokingHabits!: string | null;
  drinkingHabits!: string | null;
  fitness!: string | null;
  hobbies!: string[];
  physicalStatus!: string | null;
  familyType!: string | null;
  familyStatus!: string | null;
  familyValues!: string | null;
  fatherName!: string | null;
  fatherAge!: number | null;
  fatherOccupation!: string | null;
  motherName!: string | null;
  motherAge!: number | null;
  motherOccupation!: string | null;
  siblings!: number | null;
  siblingDetails!: Array<{
    relation: 'BROTHER' | 'SISTER';
    name?: string;
    age?: number;
    occupation?: string;
  }>;
  isProfileComplete!: boolean;
  profileCompletePct!: number;

  photos!: PhotoEntity[];
  partnerPreference!: PartnerPreferenceEntity | null;
  astrology!: AstrologyProfileEntity | null;
  completion!: ProfileCompletionEntity;
}
