import {
  IsArray,
  IsInt,
  IsNumber,
  IsObject,
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

  /**
   * The advanced preferences the standalone Partner Preferences page collects
   * (community, education/career, family, lifestyle, location, acceptance,
   * verification, plus a per-field importance map) — stored wholesale in
   * `partner_preferences.extended_preferences`.
   *
   * Without this field the page's advanced half was silently discarded: the
   * global ValidationPipe runs `forbidNonWhitelisted`, so the client could not
   * send it without the whole request 400ing, and every save reported success
   * while writing only the base fields. The column, the entity and every
   * reader (the feed's WHERE builder, the lifestyle scoring signal) already
   * existed and were being fed by the registration draft path alone.
   *
   * Deliberately permissive, exactly like the draft DTO's own `extended`: the
   * blob's internal shape is owned by the Flutter model
   * (`PartnerPreferenceExtended.toJson()`) and can evolve without a backend
   * redeploy.
   *
   * Whole-object semantics: supplying it REPLACES the stored blob (the page
   * owns all of these fields and sends them together, and the draft path
   * writes it the same way). Omitting it leaves the stored blob untouched,
   * like every other field here; `{}` clears it.
   */
  @IsOptional()
  @IsObject()
  extended?: Record<string, unknown>;
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
  /** The advanced-preferences blob, `{}` when the member has never set one.
   *  Returned so the page can hydrate what it saved — without it the client
   *  had nothing to read back and fell back to an empty object. */
  extended: Record<string, unknown>;
}
