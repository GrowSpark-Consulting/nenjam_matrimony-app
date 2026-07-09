import { IsOptional, IsString } from 'class-validator';

// Mirrors ...profile_draft.dart -> LocationDetails (step 4)
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
