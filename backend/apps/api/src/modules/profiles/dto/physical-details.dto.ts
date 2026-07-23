import { IsOptional, IsString } from 'class-validator';

// Mirrors ...profile_draft.dart -> PhysicalDetails (step 6). Body Type and
// Complexion were removed from the product (matrimony forms no longer
// collect them) — do not reintroduce them here or in physicalStatus's
// join in profile.service.ts.
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
  bloodGroup?: string;

  @IsOptional()
  @IsString()
  disability?: string;
}
