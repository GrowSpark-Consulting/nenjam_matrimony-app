// Mapped from Prisma's PartnerPreference row by ProfileRepository.
export class PartnerPreferenceEntity {
  id!: string;
  userId!: string;
  /** Null means no limit on that side ("Any", or never set). */
  minAge!: number | null;
  maxAge!: number | null;
  minHeightCm!: number | null;
  maxHeightCm!: number | null;
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
