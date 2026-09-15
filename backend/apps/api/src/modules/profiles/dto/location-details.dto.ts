import { IsOptional, IsString } from 'class-validator';

// Mirrors ...profile_draft.dart -> LocationDetails (step 4)
//
// Free strings on purpose, for now: the country/state/city option lists are
// frontend-owned (Frontend/lib/core/constants/profile_options.dart) and are
// not served by any endpoint here, so there is nothing on this side to
// whitelist against. The country -> state -> city cascade is likewise
// enforced only in Flutter — these three are stored independently and never
// checked for agreement, so a request made outside the app can persist a
// city that does not belong to its state. Documented rather than fixed:
// closing it means backend-owned master data, which is not in scope.
// Deferred master-data work is recorded in
// docs/registration/profile-options-reference-data.md.
export class LocationDetailsDto {
  @IsOptional()
  @IsString()
  country?: string;

  @IsOptional()
  @IsString()
  state?: string;

  @IsOptional()
  @IsString()
  city?: string;

  @IsOptional()
  @IsString()
  area?: string;

  @IsOptional()
  @IsString()
  pinCode?: string;

  @IsOptional()
  @IsString()
  nativePlace?: string;

  // The structured half of the location, from the frontend's master-data
  // cascade (Frontend/.../profile_draft.dart -> LocationDetails.toJson).
  //
  // These are NOT decoration: writeProfileFromDraft reads all three and
  // resolves them through LocationsService.resolve() to connect
  // countryRef/stateRef/cityRef. They were missing here while that consumer
  // already existed, and the global ValidationPipe runs with
  // `forbidNonWhitelisted: true` — so every location PATCH carrying a code
  // was rejected 400 "property countryCode should not exist". Onboarding's
  // one flush aborted on that call, never reached the section that
  // materialises the profile, and the member landed on Discover with no
  // `user_profiles` row at all.
  //
  // Still optional: a draft saved before the cascade shipped, and the
  // free-text "Other" escape, both carry text with no codes, and `resolve`
  // returns null for that case so the text stays the source of truth.
  @IsOptional()
  @IsString()
  countryCode?: string;

  @IsOptional()
  @IsString()
  stateCode?: string;

  @IsOptional()
  @IsString()
  cityCode?: string;
}
