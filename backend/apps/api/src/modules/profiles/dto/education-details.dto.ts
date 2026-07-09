import { IsOptional, IsString } from 'class-validator';

// Mirrors ...profile_draft.dart -> EducationDetails (step 5)
export class EducationDetailsDto {
  @IsOptional()
  @IsString()
  qualification?: string;

  @IsOptional()
  @IsString()
  college?: string;

  @IsOptional()
  @IsString()
  occupation?: string;

  @IsOptional()
  @IsString()
  company?: string;

  @IsOptional()
  @IsString()
  employmentType?: string;

  // Kept as a string to match the Flutter form field; parsed to a Decimal
  // (annualIncomeLakhs) only at finalize() time.
  @IsOptional()
  @IsString()
  annualIncome?: string;

  @IsOptional()
  @IsString()
  workLocation?: string;
}
