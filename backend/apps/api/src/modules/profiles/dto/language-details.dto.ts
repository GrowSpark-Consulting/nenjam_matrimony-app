import { IsArray, IsOptional, IsString } from 'class-validator';

// Mirrors ...profile_draft.dart -> LanguageDetails (step 3)
export class LanguageDetailsDto {
  @IsOptional()
  @IsString()
  motherTongue?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  languagesKnown?: string[];
}
