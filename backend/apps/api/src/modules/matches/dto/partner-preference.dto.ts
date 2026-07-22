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
// All optional: a PUT may set any subset; an omitted/empty field means "no
// preference", which the feed filter then ignores (never excludes).
export class UpdatePartnerPreferenceDto {
  @IsOptional()
  @IsInt()
  @Min(18)
  @Max(100)
  minAge?: number;

  @IsOptional()
  @IsInt()
  @Min(18)
  @Max(100)
  maxAge?: number;

  @IsOptional()
  @IsInt()
  @Min(120)
  @Max(250)
  minHeightCm?: number;

  @IsOptional()
  @IsInt()
  @Min(120)
  @Max(250)
  maxHeightCm?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  minIncomeLakhs?: number;

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
  minAge: number;
  maxAge: number;
  minHeightCm: number;
  maxHeightCm: number;
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
