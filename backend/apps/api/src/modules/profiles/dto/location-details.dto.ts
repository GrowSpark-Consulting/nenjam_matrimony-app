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
}
