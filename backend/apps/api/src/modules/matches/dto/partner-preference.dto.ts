import {
  IsArray,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';

// Fields mirror the partner_preferences table exactly — no invented columns.
// All optional: a PUT may set any subset, and an OMITTED field is left as it
// is. For the four range bounds and the minimum income, an explicit `null`
// CLEARS the limit — that is how "Any" is sent. The two must stay distinct:
// omitting could never clear a saved range, so "Any" used to leave the old
// restriction in place.
export class UpdatePartnerPreferenceDto {
  @IsOptional()
  @IsInt()
  @Min(18)
  @Max(100)
  minAge?: number | null;

  @IsOptional()
  @IsInt()
  @Min(18)
  @Max(100)
  maxAge?: number | null;

  @IsOptional()
  @IsInt()
  @Min(120)
  @Max(250)
  minHeightCm?: number | null;

  @IsOptional()
  @IsInt()
  @Min(120)
  @Max(250)
  maxHeightCm?: number | null;

  @IsOptional()
  @IsNumber()
  @Min(0)
  minIncomeLakhs?: number | null;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  preferredReligions?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  preferredCastes?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  preferredMotherTongues?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  preferredEducation?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  preferredOccupations?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  preferredCities?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  preferredStates?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  maritalStatusPref?: string[];
}

// Full preferences as returned by GET — the stored row, or schema defaults if
// the user has never set any.
export interface PartnerPreferenceResponseDto {
  /** Null: no limit on that side. */
  minAge: number | null;
  maxAge: number | null;
  minHeightCm: number | null;
  maxHeightCm: number | null;
  minIncomeLakhs: number | null;
  preferredReligions: string[];
  preferredCastes: string[];
  preferredMotherTongues: string[];
  preferredEducation: string[];
  preferredOccupations: string[];
  preferredCities: string[];
  preferredStates: string[];
  maritalStatusPref: string[];
}
