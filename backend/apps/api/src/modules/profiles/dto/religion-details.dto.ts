import { IsOptional, IsString } from 'class-validator';

// Mirrors ...profile_draft.dart -> ReligionDetails (step 2)
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
