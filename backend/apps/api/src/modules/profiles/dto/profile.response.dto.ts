import { PhotoEntity } from '../entities/photo.entity';
import { PartnerPreferenceEntity } from '../entities/partner-preference.entity';
import { AstrologyProfileEntity } from '../entities/astrology-profile.entity';
import { ProfileCompletionEntity } from '../entities/profile-completion.entity';

// Shape returned by GET /profiles/me. Field names match the Prisma
// UserProfile model (see schema.prisma), not the Flutter draft field names —
// this is the finalized, validated profile. photos/partnerPreference/
// astrology/completion are assembled from the other profiles-module
// repositories by ProfileService.getOwn(), not raw UserProfile columns.
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
  fatherOccupation!: string | null;
  motherOccupation!: string | null;
  siblings!: number | null;
  isProfileComplete!: boolean;
  profileCompletePct!: number;

  photos!: PhotoEntity[];
  partnerPreference!: PartnerPreferenceEntity | null;
  astrology!: AstrologyProfileEntity | null;
  completion!: ProfileCompletionEntity;
}
