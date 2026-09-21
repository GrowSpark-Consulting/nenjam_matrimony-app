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

  // The master-data codes the onboarding Religion step sends alongside the
  // labels (Frontend/.../profile_draft.dart -> ReligionDetails.toJson).
  //
  // Declared because the global ValidationPipe runs with
  // `forbidNonWhitelisted: true`: while these were missing, every religion
  // PATCH carrying a code was rejected 400 "property religionCode should not
  // exist". Onboarding's one flush sends sections in order inside a single
  // `try`, so that 400 skipped every section after religion — including the
  // one that materialises the profile — and registration could never
  // finalize. The same failure LocationDetailsDto's codes caused before them.
  //
  // Optional: a draft saved before the religion master data existed carries
  // labels only. The codes are kept in the draft; the free-text `religion` /
  // `community` above remain what is written to user_profiles.
  @IsOptional()
  @IsString()
  religionCode?: string;

  @IsOptional()
  @IsString()
  communityCode?: string;
}
