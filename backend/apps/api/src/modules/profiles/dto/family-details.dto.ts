import { IsInt, IsOptional, IsString, Min } from 'class-validator';

// Mirrors ...profile_draft.dart -> FamilyDetails (step 8)
export class FamilyDetailsDto {
  @IsOptional()
  @IsString()
  fatherName?: string;

  @IsOptional()
  @IsString()
  fatherOccupation?: string;

  @IsOptional()
  @IsString()
  motherName?: string;

  @IsOptional()
  @IsString()
  motherOccupation?: string;

  @IsOptional()
  @IsString()
  familyType?: string;

  @IsOptional()
  @IsString()
  familyValues?: string;

  @IsOptional()
  @IsString()
  familyStatus?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  brothers?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  sisters?: number;
}
