import { IsOptional, IsString } from 'class-validator';

// Mirrors ...profile_draft.dart -> ReligionDetails (step 2)
//
// Free strings on purpose, for now — same arrangement as
// LocationDetailsDto. The religion/community lists live in Flutter's
// ProfileOptions, no endpoint serves them, and the religion -> community
// dependency is enforced only there. Any string is accepted and stored
// verbatim in the `religion` / `community` columns.
// Deferred master-data work is recorded in
// docs/registration/profile-options-reference-data.md.
export class ReligionDetailsDto {
  @IsOptional()
  @IsString()
  religion?: string;

  @IsOptional()
  @IsString()
  caste?: string;

  @IsOptional()
  @IsString()
  subCaste?: string;

  @IsOptional()
  @IsString()
  gothra?: string;

  @IsOptional()
  @IsString()
  denomination?: string;

  @IsOptional()
  @IsString()
  community?: string;
}
