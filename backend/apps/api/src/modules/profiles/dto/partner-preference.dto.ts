import { IsObject, IsOptional, IsString } from 'class-validator';

// Mirrors ...profile_draft.dart -> PartnerPreference (step 10).
// Kept as free-text range strings to match the Flutter form; parsed into
// PartnerPreference's numeric min/max + JSON array columns at finalize().
export class PartnerPreferenceDto {
  @IsOptional()
  @IsString()
  preferredAgeRange?: string;

  @IsOptional()
  @IsString()
  preferredHeightRange?: string;

  @IsOptional()
  @IsString()
  religionPref?: string;

  @IsOptional()
  @IsString()
  castePref?: string;

  @IsOptional()
  @IsString()
  educationPref?: string;

  @IsOptional()
  @IsString()
  occupationPref?: string;

  @IsOptional()
  @IsString()
  incomePref?: string;

  @IsOptional()
  @IsString()
  locationPref?: string;

  @IsOptional()
  @IsString()
  motherTonguePref?: string;

  @IsOptional()
  @IsString()
  maritalStatusPref?: string;

  // Advanced fields from the standalone Partner Preferences page — kept
  // permissive (no nested DTO/whitelist) since this blob's internal shape
  // is owned by the Flutter client (PartnerPreferenceExtended.toJson()) and
  // can evolve without a backend redeploy, same as draftData itself. Stored
  // as-is in partner_preferences.extended_preferences at finalize().
  @IsOptional()
  @IsObject()
  extended?: Record<string, unknown>;
}
