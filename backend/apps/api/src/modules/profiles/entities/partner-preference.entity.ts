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
  // Advanced fields (religion/community, education/career, family,
  // lifestyle, location, special cases, verification filters, per-criterion
  // requirement tags) from the standalone Partner Preferences page. Free-form
  // — mirrors Frontend's PartnerPreferenceExtended.toJson().
  extendedPreferences!: Record<string, unknown>;
}
