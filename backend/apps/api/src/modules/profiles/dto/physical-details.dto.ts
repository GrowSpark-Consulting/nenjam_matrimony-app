import { IsOptional, IsString } from 'class-validator';

// Mirrors ...profile_draft.dart -> PhysicalDetails (step 6)
// height/weight kept as strings to match the Flutter form fields; parsed to
// heightCm (Int) / weightKg (Int) only at finalize() time.
export class PhysicalDetailsDto {
  @IsOptional()
  @IsString()
  height?: string;

  @IsOptional()
  @IsString()
  weight?: string;

  @IsOptional()
  @IsString()
  bodyType?: string;

  @IsOptional()
  @IsString()
  complexion?: string;

  @IsOptional()
  @IsString()
  bloodGroup?: string;

  @IsOptional()
  @IsString()
  disability?: string;
}
