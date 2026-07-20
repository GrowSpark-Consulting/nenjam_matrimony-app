// Mapped from Prisma's PartnerPreference row by ProfileRepository.
export class PartnerPreferenceEntity {
  id!: string;
  userId!: string;
  minAge!: number;
  maxAge!: number;
  minHeightCm!: number;
  maxHeightCm!: number;
  preferredReligions!: string[];
  preferredCastes!: string[];
  minIncomeLakhs!: string | null;
  preferredCities!: string[];
  preferredStates!: string[];
  preferredEducation!: string[];
  preferredOccupations!: string[];
  preferredMotherTongues!: string[];
  maritalStatusPref!: string[];
}
